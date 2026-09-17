# `slack` 1.0.0

Slack messaging client. Sends messages to channels, resolves user mentions by email, and supports Block Kit formatting. Copy the slack/ folder into a node and add it to package.path.

| | |
|---|---|
| **Library** | `slack` |
| **Version** | 1.0.0 |
| **Immutable** | yes — a fix ships as a new version directory |

## Modules

- `slack/slack.lua`
- `slack/slack_http.lua`

## Using it

A node that pins this library gets the `slack/` folder copied in beside its script. Add it to `package.path` and require the entry module:

```lua
local slack = require("slack.slack")
```
