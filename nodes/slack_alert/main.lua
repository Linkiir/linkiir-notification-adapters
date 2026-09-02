-- ---------------------------------------------------------------------------
-- Slack Alert - Transform Notification Alert
--
-- Receives notification alerts and posts them to a configured Slack channel.
-- Optionally resolves an email to a Slack user mention and appends it.
-- Passes the alert data downstream for further processing or logging.
--
-- This is a transform node: it sends the alert to Slack AND passes data
-- downstream, so you can chain additional notifiers or logging after it.
--
-- What to change where:
--   API Token, Channel ID, Mention Email   ->  node config
--   how the alert becomes a message        ->  this script (FormatAlert)
--   how Slack is called                    ->  slack library
-- ---------------------------------------------------------------------------

-- The library modules live in the slack/ subfolder.
package.path = linkiir.sys.nodeDir() .. '/slack/?.lua;' .. package.path

local Slack = require 'slack'

-- Format a timestamp string (ISO 8601) into a human-readable form.
local function FormatTimestamp(Timestamp)
   if not Timestamp or Timestamp == '' then return '' end
   local Y, M, D, h, m, s = Timestamp:match('(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+)')
   if not Y then return Timestamp end
   local TimeTable = {
      year  = tonumber(Y),
      month = tonumber(M),
      day   = tonumber(D),
      hour  = tonumber(h),
      min   = tonumber(m),
      sec   = tonumber(s),
   }
   return os.date('%B %d, %Y at %I:%M %p', os.time(TimeTable))
end

-- Build a Slack message from an alert payload.
-- Handles both structured JSON alerts and plain text messages.
local function FormatAlert(Data)
   local Ok, Alert = pcall(linkiir.json.parse, Data)

   if not Ok or type(Alert) ~= 'table' then
      -- Plain text message — use as-is
      return Data
   end

   -- Structured alert: build a formatted message
   local RuleName  = Alert.rule_name or Alert.alert_name or 'unknown'
   local Body      = Alert.message or Alert.summary or Alert.description or ''
   local Source    = Alert.source or Alert.workflow_id or Alert.origin or ''
   local Severity  = Alert.severity or Alert.level or ''
   local Timestamp = Alert.timestamp or Alert.last_event_time or Alert.first_event_time or ''

   local Parts = {}
   Parts[#Parts + 1] = '*Alert: ' .. RuleName .. '*'
   if Severity ~= '' then
      Parts[#Parts + 1] = 'Severity: ' .. Severity
   end
   if Body ~= '' then
      Parts[#Parts + 1] = 'Message: ' .. Body
   end
   if Source ~= '' then
      Parts[#Parts + 1] = 'Source: ' .. Source
   end
   if Timestamp ~= '' then
      Parts[#Parts + 1] = 'Time: ' .. FormatTimestamp(Timestamp)
   end

   return table.concat(Parts, '\n')
end

function main(Data)
   local S, Config = Slack.fromNodeConfig()

   local ChannelId = Config['Channel ID']
   if not ChannelId or ChannelId == '' then
      linkiir.log.error('Slack Alert: Channel ID is not configured.')
      return
   end

   if not Data or Data == '' then
      linkiir.log.warn('Slack Alert: received empty inbound data, nothing to send.')
      return
   end

   -- Format the alert into a Slack message
   local Text = FormatAlert(Data)

   -- Optionally resolve an email to a user mention and append it.
   local Email = Config['Mention Email']
   if Email and Email ~= '' then
      local Tag, Err = S:userTagByEmail{ email = Email }
      if Tag then
         Text = Text .. ' ' .. Tag
      else
         linkiir.log.warn(string.format(
            'Slack Alert: could not resolve mention for %s [%s] %s',
            Email, tostring(Err.code), tostring(Err.message)))
      end
   end

   local Result, Err = S:message{
      channel = ChannelId,
      text    = Text,
   }

   if not Result then
      linkiir.log.error(string.format('Slack Alert: message failed [%s] %s',
         tostring(Err.code), tostring(Err.message)))
      return
   end

   if Result.simulated then
      linkiir.log.info('Slack Alert: Live Mode is off, no message was sent.')
      -- Still push downstream so the rest of the pipeline can test
      linkiir.flow.push{ data = Data }
      return
   end

   linkiir.log.info('Slack Alert: message posted to channel ' .. ChannelId)

   -- Pass the original alert data downstream for further processing
   linkiir.flow.push{ data = Data }
end
