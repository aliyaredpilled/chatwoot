# atta2 deploy plan for Max Chatwoot MVP

This note assumes we want a quick functional test on atta2.

## Current status

- local branch exists: `codex/max-chatwoot-mvp`
- fork exists: `https://github.com/aliyaredpilled/chatwoot`
- branch push did not complete because GitHub timed out from this environment
- local patch file exists at:
  - `/Users/aliya/настройка-4-ботов/chatwoot-max-mvp.patch`

## Fastest path on atta2

### Option A: apply the patch to a fresh Chatwoot clone

```bash
cd ~
git clone --depth 1 https://github.com/chatwoot/chatwoot.git
cd chatwoot
git checkout -b codex/max-chatwoot-mvp
git apply /path/to/chatwoot-max-mvp.patch
```

### Option B: once branch push works later

```bash
cd ~
git clone --depth 1 -b codex/max-chatwoot-mvp https://github.com/aliyaredpilled/chatwoot.git
cd chatwoot
```

## Boot commands

```bash
cp .env.example .env
bundle install
pnpm install
RAILS_ENV=development bundle exec rails db:prepare
bundle exec sidekiq -C config/sidekiq.yml
bundle exec rails s -b 0.0.0.0 -p 3000
```

If using docker compose instead:

```bash
cp .env.example .env
docker compose up --build
```

## Create a Max inbox through API

Use the normal inbox create endpoint and set `channel.type` to `max`.

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

## What this MVP supports

- direct messages only
- outbound text replies
- polling every minute through sidekiq-cron
- per-user `user_id -> chat_id` mapping for replies

## What still needs work after the first live test

- attachments
- group chats
- dedicated dashboard setup form
- automated tests
