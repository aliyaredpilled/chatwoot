# Umnico Integration — Прогресс и статус

## Что сделано

### Backend (Ruby)
- **Channel::Umnico модель** (`app/models/channel/umnico.rb`) — с авто-генерацией webhook_secret, валидацией токена через `/v1.3/account/me`, авторегистрацией/удалением вебхука в Umnico
- **Umnico API клиент** (`app/services/umnico/api_client.rb`) — auth, leads, messaging, webhooks CRUD, upload, managers
- **Incoming message service** (`app/services/umnico/incoming_message_service.rb`) — парсинг webhook payload, создание contact/conversation/message, вложения, дедупликация
- **Send service** (`app/services/umnico/send_on_umnico_service.rb`) — отправка через lead_id + source (realId) + userId (из managers API), чанкинг текста, вложения
- **Webhook controller** (`app/controllers/webhooks/umnico_controller.rb`) — принимает POST, отдаёт 200
- **Webhook events job** (`app/jobs/webhooks/umnico_events_job.rb`) — async обработка через Sidekiq
- **Миграция** (`db/migrate/20260329120000_create_channel_umnico.rb`) — таблица channel_umnico

### Патчи в существующих файлах
- `config/routes.rb` — `post 'webhooks/umnico/:webhook_secret'`
- `app/jobs/send_reply_job.rb` — `'Channel::Umnico' => ::Umnico::SendOnUmnicoService`
- `app/models/account.rb` — `has_many :umnico_channels`
- `app/models/inbox.rb` — `umnico?` метод + `callback_webhook_url`
- `app/controllers/api/v1/accounts/inboxes_controller.rb` — `'umnico'` в allowed_channel_types + channel_type_from_params
- `app/helpers/api/v1/inboxes_helper.rb` — `'umnico'` в account_channels_method

### Frontend (JS/Vue)
- `app/javascript/dashboard/helper/inbox.js` — INBOX_TYPES.UMNICO, иконки, readable name
- `app/javascript/dashboard/components-next/icon/provider.js` — иконка канала
- `app/javascript/shared/mixins/inboxMixin.js` — REPLY_TO, REPLY_TO_OUTGOING features
- `app/javascript/dashboard/composables/useInbox.js` — `isAUmnicoChannel` computed
- `app/javascript/dashboard/components-next/message/MessageMeta.vue` — fallback для галочек: любой неизвестный канал с sourceId показывает sent/delivered

## Деплой на atta2

### Инфраструктура
- **Тестовый Chatwoot:** `http://10.3.255.150:3100` (docker-compose.max.yml)
- **Docker image:** `chatwoot-max:test` (overlay поверх `chatwoot/chatwoot:latest`)
- **Dockerfile:** `Dockerfile.max-overlay` — копирует Ruby-файлы + pre-built vite assets
- **Логин:** `admin@test.local` / `Password1!`
- **Account ID:** 1, **Inbox ID:** 1

### Umnico
- **API токен:** `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJhY2NvdW50SWQiOjE2MjU0NSwiY3JlYXRpb25EYXRlIjoiMjAyNi0wMy0yOFQxNTo1MzozMi43MjJaIiwiaWF0IjoxNzc0NzEzMjEyfQ.uOyteG-xHkhN7XPkmoLB8Vb_5mMHFXHXSTqNm3LojUk`
- **Account ID:** 162545
- **User ID (owner):** 2430957
- **Webhook ID:** 30188
- **Webhook secret:** `22164b32ea0c3554fa5cc4739c838e77899590a7`

### Nginx прокси (wamm-nginx)
Вебхуки от Umnico приходят через `support.skynet-kazan.com` → wamm-nginx (порт 3000) → наш Chatwoot (порт 3100):
```
location /webhooks/umnico/ {
    proxy_pass http://172.17.0.1:3100;
    ...
}
```
**Важно:** при перезапуске контейнера wamm-nginx конфиг сбросится (он генерится через CMD). Нужно повторно добавлять location.

### Пересборка
```bash
# На atta2:
cd ~/chatwoot-max-test
docker build -f Dockerfile.max-overlay -t chatwoot-max:test .
docker compose -f docker-compose.max.yml up -d
```

### Frontend пересборка (локально на маке)
```bash
# В /Users/aliya/настройка-4-ботов/chatwoot/
pnpm install --frozen-lockfile
SECRET_KEY_BASE=precompile_placeholder RAILS_ENV=production npx vite build
tar czf /tmp/vite-assets.tar.gz public/vite/
# scp на atta2, распаковать в ~/chatwoot-max-test/public/vite/
```

## Сложности и решения

### 1. Формат webhook payload
**Проблема:** Бриф предполагал что webhook содержит только `leadId`, а тело нужно дозапрашивать. В реальности webhook `message.incoming` содержит полный объект `message` с вложенным `message.message.text`.
**Решение:** Переписали IncomingMessageService — парсим данные прямо из webhook payload.

### 2. Обязательные поля при отправке (source + userId)
**Проблема:** Umnico API `/messaging/<lead-id>/send` требует `source` (числовой realId канала) и `userId` (ID сотрудника). Без них — 422.
**Решение:**
- `source` — сохраняем `webhook_message.dig('source', 'realId')` в `conversation.additional_attributes['umnico_source']`
- `userId` — получаем через `GET /v1.3/managers` (берём owner), кешируется на время запроса

### 3. source.id vs source.realId
**Проблема:** `source.id` (например `user_7715692646`) содержит буквы, а API требует `"string consisting of numbers (maybe _)"`.
**Решение:** Используем `source.realId` (например `76919905`).

### 4. Часики в UI (message status)
**Проблема:** Chatwoot frontend не знал про Channel::Umnico и показывал PROGRESS (часики) для всех исходящих сообщений.
**Решение:** Добавили fallback в `MessageMeta.vue` — любой неизвестный канал с `sourceId` считается `sent`. Потребовалась пересборка vite assets (локально на маке, т.к. на серверах OOM).

### 5. OOM при сборке frontend
**Проблема:** Vite build требует ~3-4GB RAM. На atta2 (8GB, много контейнеров) — OOM. На vps5 (15GB) — нет места на диске.
**Решение:** Собираем frontend локально на маке (16GB), пакуем `public/vite/` в tar.gz, копируем на atta2.

### 6. wamm-nginx конфиг не персистентный
**Проблема:** Конфиг wamm-nginx генерится через Docker CMD — при рестарте контейнера наш location `/webhooks/umnico/` пропадёт.
**Решение пока:** Ручное добавление через `docker cp`. TODO: добавить в docker-compose wamm или volume mount.

### 7. FRONTEND_URL
**Проблема:** `FRONTEND_URL=https://support.skynet-kazan.com` ломает UI при доступе через внутренний IP.
**Решение:** Оставили `FRONTEND_URL=http://10.3.255.150:3100`. Вебхуки работают через nginx прокси независимо.

## TODO для production

- [ ] Перенести на основной Chatwoot (порт 3002, `telecom-support-chatwoot`)
- [ ] Персистентный nginx конфиг для umnico webhook route
- [ ] Мониторинг статуса вебхука (Umnico может деактивировать при недоступности)
- [ ] Обработка `message.outgoing` event (для статуса delivered/read)
- [ ] Фильтрация групповых чатов (сейчас создаются conversations для group messages из Max)

## Git
- **Форк:** https://github.com/aliyaredpilled/chatwoot
- **Ветка:** `codex/max-chatwoot-mvp`
- **Коммиты:** `2bfc094` (Max), `7e6fed1` (Umnico)
