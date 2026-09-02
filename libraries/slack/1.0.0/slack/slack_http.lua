-- ---------------------------------------------------------------------------
-- slack_http - the request path every Slack API call goes through
--
-- Attaches the bearer token, builds the API URL, sends the request, and turns
-- whatever Slack returns into one predictable pair:
--
--    Result        - the parsed response body (Slack JSON envelope)
--    nil, Err      - Err is { code=, message= } plus optional context
--
-- Slack API responses always return HTTP 200 with a JSON body containing an
-- `ok` field. A false `ok` carries an `error` string describing what went wrong.
-- ---------------------------------------------------------------------------

local M = {}

local SLACK_API_BASE = 'https://slack.com/api/'

-- Build request headers. The API Token is attached as a Bearer token.
local function buildHeaders(Token, Extra)
   local Headers = {}
   for Key, Value in pairs(Extra or {}) do
      Headers[Key] = Value
   end
   Headers['Authorization'] = 'Bearer ' .. Token
   return Headers
end

-- Parse and classify a Slack API response.
local function readBody(Response, Method, Url)
   if not Response then
      return nil, {
         code    = 'REQUEST_FAILED',
         message = Method:upper() .. ' ' .. Url .. ' failed',
      }
   end

   if Response.simulated then
      return { simulated = true }
   end

   if Response.body == nil or Response.body == '' then
      return nil, {
         code      = 'EMPTY_RESPONSE',
         message   = 'Slack returned an empty response body',
         http_code = Response.code,
      }
   end

   local Ok, Parsed = pcall(linkiir.json.parse, Response.body)
   if not Ok then
      return nil, {
         code      = 'PARSE_ERROR',
         message   = 'Slack response was not valid JSON',
         http_code = Response.code,
         body      = Response.body,
      }
   end

   if Response.code < 200 or Response.code >= 300 then
      return nil, {
         code      = 'HTTP_' .. tostring(Response.code),
         message   = 'Slack returned HTTP ' .. tostring(Response.code),
         http_code = Response.code,
         body      = Parsed,
      }
   end

   if not Parsed.ok then
      return nil, {
         code    = 'SLACK_ERROR',
         message = Parsed.error or 'Slack returned ok=false without an error string',
         body    = Parsed,
      }
   end

   return Parsed
end

-- Send one Slack API request.
--
--   Client       - the slack client instance (carries .token, .live, .timeout)
--   T.method     - HTTP verb, defaults to 'post'
--   T.api        - Slack Web API method name, e.g. 'chat.postMessage'
--   T.body       - request body (JSON-serialised and sent as application/json)
--   T.params     - query string parameters (for GET requests)
--   T.headers    - extra headers
--   T.live       - overrides the client's live flag for this call
function M.request(Client, T)
   local Method = tostring(T.method or 'post'):lower()
   local SendRequest = linkiir.link.web[Method]
   if not SendRequest then
      error("slack_http.request: unsupported HTTP method '" .. Method .. "'")
   end

   local Headers = buildHeaders(Client.token, T.headers)

   local Live = T.live
   if Live == nil then Live = Client.live end
   if Live == nil then Live = true end

   local Url = SLACK_API_BASE .. tostring(T.api)

   local Request = {
      url       = Url,
      headers   = Headers,
      timeout   = Client.timeout,
      verifyTls = Client.verify_tls,
      live      = Live,
   }

   if Method == 'get' then
      Request.params = T.params
   else
      if T.body ~= nil then
         Request.body = linkiir.json.serialize(T.body)
         Headers['Content-Type'] = 'application/json; charset=utf-8'
      end
   end

   linkiir.log.debug('slack ' .. Method:upper() .. ' ' .. Url)

   local Response, WebErr = SendRequest(Request)
   if not Response then
      return nil, WebErr or {
         code    = 'REQUEST_FAILED',
         message = Method:upper() .. ' ' .. Url .. ' failed',
      }
   end

   return readBody(Response, Method, Url)
end

return M
