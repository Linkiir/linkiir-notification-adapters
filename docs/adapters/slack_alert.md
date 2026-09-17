# Slack Alert

Receives notification alerts and posts them to a Slack channel. Optionally resolves an email to a user mention. Passes alert data downstream for further processing.

| | |
|---|---|
| **Slug** | `slack_alert` |
| **Node type id** | `LKNOTIF_SLACK_ALERT` |
| **Node type** | transform |
| **Version** | 1.0.0 |
| **Interval driven** | no |
| **Libraries** | slack 1.0.0 |

## Configuration

| Field | Type | Default | Notes |
|---|---|---|---|
| API Token | password | _(empty — set on the node)_ | Slack Bot User OAuth Token (starts with xoxb-). Created in the Slack App settings under OAuth & Permissions. |
| Channel ID | string | _(empty)_ | The Slack channel ID to post messages to. Find it by right-clicking the channel name and choosing Copy Link — the ID is the last path segment. |
| Mention Email | string | _(empty)_ | Optional. An email address to resolve to a Slack user mention and append to the message. Leave empty to send the message without a mention. |
| Live Mode | bool | `true` | When off, API requests are simulated and no message is sent. Useful while wiring up the workflow. |
| Verify TLS | bool | `true` | Whether to verify the Slack server's TLS certificate. Leave on outside of local testing behind a proxy. |

## Samples

De-identified messages you can run the node against:

- `samples/patient_alert.txt`
