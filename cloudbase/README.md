# PagePilot Feedback

Flow: `PagePilot -> pagepilotFeedback -> pagepilotUserFeedback -> private PagePilot Feishu group`.

The function uses a dedicated signature and collections. It accepts the message, app and OS versions, and an app-instance ID for rate limiting. Only an hourly hash of the instance ID is stored in rate-limit records. Limits match BeforeShow: five submissions per instance per hour, and 120 globally per hour.

## Local Checks

```sh
npm test
```

## Deployment

Configure the following in an ignored `cloudbase/.env` file:

- `TCB_ENV_ID`
- `TCB_REGION`
- `FEISHU_APP_ID`
- `FEISHU_APP_SECRET`
- `PAGEPILOT_FEISHU_CHAT_ID`

Deploy from this directory with the CloudBase CLI:

```sh
tcb fn deploy pagepilotFeedback --httpFn --path /pagepilotFeedback
```

Do not embed Feishu credentials or webhook URLs in the iOS app. The function acknowledges stored feedback even if Feishu notification fails; `notificationDelivered` reports the checked Feishu API result, and failures are logged.

Deployed on 2026-10-09 to the existing Shanghai CloudBase environment, with dedicated PagePilot collections and private group `PagePilot 反馈`. BeforeShow functions and its feedback group are unchanged.

Endpoint: `https://beforeshow-d2g0gv0zz4cc249dc-1312569550.ap-shanghai.app.tcloudbase.com/pagepilotFeedback`. The HTTP gateway route must use type `6` (HTTP function), not type `1` (event function).
