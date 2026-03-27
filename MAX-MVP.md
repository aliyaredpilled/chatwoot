# Max Channel MVP

This repository now contains a backend-first MVP for a Max Bot API channel.

## Included

- `Channel::Max` model
- Max Bot API client
- scheduled polling jobs
- inbound direct-message ingestion
- outbound text delivery
- `user_id -> chat_id` mapping for replies
- inbox creation support through the existing inbox API

## Current limitations

- direct messages only
- no attachments yet
- no group chat ingestion
- no dedicated dashboard creation form yet
- no automated tests yet

## Files

- `app/models/channel/max.rb`
- `app/jobs/channels/max_polling_scheduler_job.rb`
- `app/jobs/channels/max_polling_job.rb`
- `app/services/max/api_client.rb`
- `app/services/max/incoming_message_service.rb`
- `app/services/max/send_on_max_service.rb`
- `db/migrate/20260327214500_create_channel_max.rb`

## Scheduler

The polling scheduler is registered in `config/schedule.yml` as:

- `Channels::MaxPollingSchedulerJob` every minute

Each run enqueues per-channel polling jobs for active Max channels.

## Create inbox through API

Until the dashboard form exists, create a Max inbox through the regular inbox endpoint.

Example payload:

```json
{
  "name": "Max Support",
  "channel": {
    "type": "max",
    "bot_token": "YOUR_MAX_BOT_TOKEN",
    "enabled": true,
    "polling_interval_seconds": 20
  }
}
```

## Recommended next steps

1. Run the migration.
2. Create a Max inbox through the API.
3. Start Sidekiq with cron enabled.
4. Send a DM to the Max bot.
5. Reply from Chatwoot and confirm outbound delivery.
6. Then add attachments and dashboard UI.
