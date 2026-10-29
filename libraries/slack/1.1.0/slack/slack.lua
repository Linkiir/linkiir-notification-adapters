-- ---------------------------------------------------------------------------
-- slack - Slack messaging client
--
-- Require this module. The other (slack_http) is an internal.
--
--    local Slack = require 'slack'
--
--    function main(Data)
--       local S = Slack.fromNodeConfig()
--
--       local Result, Err = S:message{
--          channel = S.channel_id,
--          text    = Data,
--       }
--       if not Result then
--          linkiir.log.error(Err.message)
--          return
--       end
--    end
--
-- Every method returns a result, or nil plus an error table:
--
--    local Result, Err = S:userTagByEmail{ email = 'user@example.com' }
--    if not Result then
--       -- Err.code and Err.message are always set.
--    end
--
-- Authentication is a static bearer token: the configured API Token is sent
-- directly in the Authorization header on every request. There is no token
-- exchange or refresh.
-- ---------------------------------------------------------------------------

local Http = require 'slack_http'

local DEFAULT_TIMEOUT = 30

-- ---------------------------------------------------------------------------
-- Email-to-user-tag cache (module-level, persists across invocations within
-- the same node process)
-- ---------------------------------------------------------------------------

local UserTagCache = {}

-- ---------------------------------------------------------------------------
-- Client methods
-- ---------------------------------------------------------------------------

local Client = {}
Client.__index = Client

-- Post a message to a channel.
--
--   T.channel - Slack channel ID
--   T.text    - message text (used as fallback and notification text)
--   T.blocks  - optional Block Kit blocks (JSON-serialisable table)
--   T.live    - overrides the client's live flag for this call
--
-- Returns the Slack response (including ts, channel) or nil, err.
function Client:message(T)
   local Body = {
      channel      = T.channel,
      text         = T.text or 'No text was supplied',
      unfurl_links = false,
      unfurl_media = false,
   }
   if T.blocks then Body.blocks = T.blocks end

   return Http.request(self, {
      method = 'post',
      api    = 'chat.postMessage',
      body   = Body,
      live   = T.live,
   })
end

-- Resolve an email address to a Slack user mention tag (<@USER_ID>).
--
-- Results are cached per email for the lifetime of the process to avoid
-- redundant API calls.
--
--   T.email - the email address to look up
--   T.live  - overrides the client's live flag for this call
--
-- Returns the mention string (e.g. "<@U12345>") or nil, err.
function Client:userTagByEmail(T)
   local Email = T.email
   if not Email or Email == '' then
      return nil, {
         code    = 'INVALID_INPUT',
         message = 'email is required for userTagByEmail',
      }
   end

   -- Return cached result if available
   if UserTagCache[Email] then
      return UserTagCache[Email]
   end

   local Result, Err = Http.request(self, {
      method = 'get',
      api    = 'users.lookupByEmail',
      params = { email = Email },
      live   = T.live,
   })

   if not Result then return nil, Err end

   if Result.simulated then
      return '<@SIMULATED>'
   end

   if not Result.user or not Result.user.id then
      return nil, {
         code    = 'USER_NOT_FOUND',
         message = 'Slack returned no user for email: ' .. Email,
      }
   end

   local Tag = '<@' .. Result.user.id .. '>'
   UserTagCache[Email] = Tag
   return Tag
end

-- Send a custom Slack Web API request. Escape hatch for anything the methods
-- above do not cover.
--
--   T.api     - Slack Web API method name (e.g. 'conversations.list')
--   T.method  - HTTP verb, defaults to 'post'
--   T.body    - request body (for POST/PUT)
--   T.params  - query params (for GET)
--   T.headers - extra headers
--   T.live    - overrides the client's live flag
function Client:request(T)
   return Http.request(self, T)
end

-- ---------------------------------------------------------------------------
-- Block Kit helpers
-- ---------------------------------------------------------------------------

-- Build a text object for Block Kit.
--
--   T.text      - the text content
--   T.text_type - 'mrkdwn' (default) or 'plain_text'
local function createText(T)
   return {
      type = T.text_type or 'mrkdwn',
      text = T.text,
   }
end

-- Build a Block Kit section block with optional accessory.
--
--   T.text       - section text
--   T.text_type  - 'mrkdwn' or 'plain_text'
--   T.accessory  - optional accessory table { type=, text=, url= }
local function createSection(T)
   local Block = {
      type = 'section',
      text = createText(T),
   }
   if T.accessory then
      Block.accessory = {
         type = T.accessory.type,
         text = createText(T.accessory),
         url  = T.accessory.url,
      }
   end
   return Block
end

-- ---------------------------------------------------------------------------
-- Module
-- ---------------------------------------------------------------------------

local M = {}

M.Client = Client
M.createText = createText
M.createSection = createSection

-- Build a client explicitly.
--
--   Token     - Slack Bot User OAuth Token (xoxb-...)
--   ChannelId - default channel ID for messages
--   Timeout   - request timeout in seconds, defaults to 30
--   VerifyTls - verify the server certificate, defaults to true
--   Live      - perform real API requests, defaults to true
function M.new(T)
   T = T or {}

   if not T.Token or T.Token == '' then
      error('slack.new: Token is required')
   end

   local Instance = setmetatable({}, Client)
   Instance.token      = T.Token
   Instance.channel_id = T.ChannelId or ''
   Instance.timeout    = tonumber(T.Timeout) or DEFAULT_TIMEOUT
   Instance.verify_tls = T.VerifyTls ~= false
   Instance.live       = T.Live ~= false

   return Instance
end

-- Build a client from the current node's own configuration fields.
--
-- Returns the client and the raw config table, so a script can read its own
-- additional fields without a second linkiir.config.node() call:
--
--    local S, Config = Slack.fromNodeConfig()
function M.fromNodeConfig()
   local Config = linkiir.config.node()

   local Instance = M.new{
      Token     = Config['API Token'],
      ChannelId = Config['Channel ID'],
      VerifyTls = Config['Verify TLS'],
      Live      = Config['Live Mode'],
   }

   return Instance, Config
end

return M
