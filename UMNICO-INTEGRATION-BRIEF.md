# Бриф: интеграция Умнико (Umnico) в Chatwoot

## Задача

Добавить в Chatwoot новый тип канала **Channel::Umnico** — единый канал через платформу [Umnico](https://umnico.com), который объединяет Max, Telegram, WhatsApp, VK и другие мессенджеры через один API.

Вместо отдельных интеграций на каждый мессенджер — один канал-адаптер через Umnico API v1.3.

## Почему Umnico а не отдельные каналы

- Один API на все мессенджеры (Max, Telegram, WhatsApp, VK, Instagram, Viber, Discord, Avito, Email)
- Вебхуки (мгновенная доставка, не polling)
- Единый формат сообщений и вложений
- Управление каналами через UI Umnico, в Chatwoot только приём/отправка

## Umnico API — ключевые моменты

### Аутентификация

- Base URL: `https://api.umnico.com/v1.3/`
- JWT токен из Settings > API в интерфейсе Umnico
- Заголовок: `Authorization: bearer <JWT Token>`

### Вебхуки (входящие сообщения)

Umnico шлёт POST на наш URL при событиях. До 10 вебхуков на аккаунт.

Управление:
- `POST /v1.3/webhooks/` — создать (`url`, `name`)
- `GET /v1.3/webhooks/` — список
- `PUT /v1.3/webhooks/<id>` — обновить
- `DELETE /v1.3/webhooks/<id>` — удалить

Типы событий:
- `message.incoming` — входящее сообщение
- `message.outgoing` — исходящее
- `lead.created` — новое обращение (≈ новый разговор)
- `lead.changed.status` — смена статуса
- `customer.created` — новый клиент

Формат входящего сообщения:
```json
{
  "type": "message.incoming",
  "accountId": 123,
  "leadId": 456,
  "isNewLead": true,
  "isNewCustomer": false
}
```

После получения webhook нужно запросить детали сообщения через API.

### Отправка сообщений

В существующий лид:
```
POST /v1.3/messaging/<lead-id>/send
{
  "message": {
    "text": "Текст",
    "attachment": {
      "type": "photo",
      "media": { "id": 123, "url": "https://..." }
    }
  },
  "source": "255",
  "userId": 15
}
```

### Вложения

Типы: `photo`, `doc`, `video`, `audio`, `sticker`, `link`

Загрузка:
```
POST /v1.3/messaging/upload
Content-Type: multipart/form-data
```

### Каналы в Umnico (типы интеграций)

| Тип Umnico | Канал |
|------------|-------|
| `ok` | **Max** (бывший OK Messenger) |
| `telebot` | Telegram Bot |
| `telegram` | Telegram Personal |
| `whatsapp2` | WhatsApp |
| `waba` | WhatsApp Business API |
| `vk_group` | VKontakte |
| `fb_messenger` | Facebook Messenger |
| `instagramV3` | Instagram |
| `viber_bot` | Viber |
| `discord` | Discord |

### Ключевые сущности

- **Integration (sa)** — подключённый канал (Telegram-бот, WhatsApp-номер и т.д.)
- **Customer** — клиент (может иметь контакты в разных мессенджерах)
- **Lead** — обращение (≈ conversation в Chatwoot)
- **Message** — сообщение внутри лида

### Rate limits

- Явных лимитов на API не задокументировано
- Write First: WhatsApp — 2500/день, Telegram Personal — 100/день
- Пагинация: max 200 записей/запрос

## Образец: как устроен канал в Chatwoot

Мы уже сделали Max-канал как MVP — его можно использовать как шаблон. Файлы:

### Новые файлы (создать аналогичные для Umnico)

- `app/models/channel/umnico.rb` — модель канала
- `app/services/umnico/api_client.rb` — HTTP-клиент Umnico API
- `app/services/umnico/incoming_message_service.rb` — обработка входящих
- `app/services/umnico/send_on_umnico_service.rb` — отправка ответов
- `app/controllers/api/v1/accounts/umnico_controller.rb` — webhook endpoint
- `db/migrate/xxx_create_channel_umnico.rb` — миграция

### Существующие файлы (добавить Umnico)

- `app/controllers/api/v1/accounts/inboxes_controller.rb` — добавить `'umnico' => Channel::Umnico`
- `app/helpers/api/v1/inboxes_helper.rb` — добавить в `channel_attributes_for`
- `app/jobs/send_reply_job.rb` — добавить `'Channel::Umnico' => ::Umnico::SendOnUmnicoService`
- `app/models/account.rb` — `has_many :umnico_channels`
- `app/models/inbox.rb` — добавить `umnico?` метод
- `config/routes.rb` — добавить webhook route

### Ключевые отличия от Max-канала

1. **Вебхуки вместо polling** — не нужны scheduler/polling jobs, нужен webhook controller
2. **Мульти-канал** — одна интеграция Umnico = много мессенджеров, нужно хранить какой мессенджер в `additional_attributes`
3. **Lead-based** — Umnico работает через leads (обращения), нужен маппинг lead_id ↔ conversation
4. **Вложения из коробки** — Umnico унифицирует формат вложений

## Модель Channel::Umnico — предлагаемая схема

```ruby
# Table: channel_umnico
#   id                :bigint, PK
#   account_id        :integer, not null
#   api_token         :string, not null (JWT токен Umnico)
#   webhook_secret    :string (для верификации вебхуков)
#   webhook_id        :string (ID зарегистрированного вебхука в Umnico)
#   umnico_account_id :integer (ID аккаунта в Umnico)
#   lead_map          :jsonb, default {} (lead_id → conversation_id маппинг)
#   enabled           :boolean, default true
#   created_at, updated_at
```

## Webhook flow

```
Юзер пишет в Max/Telegram/WhatsApp
  → Umnico получает сообщение
  → Umnico шлёт POST на наш webhook URL
  → UmnicoController#receive
  → Umnico::IncomingMessageService
    → находит/создаёт contact
    → находит/создаёт conversation (через lead_id маппинг)
    → создаёт message (с вложениями если есть)

Оператор отвечает в Chatwoot
  → SendReplyJob → Umnico::SendOnUmnicoService
  → POST /v1.3/messaging/<lead-id>/send
  → Umnico доставляет в нужный мессенджер
```

## Деплой

- Сервер: atta2 (10.3.255.150), пользователь kvb
- Подключение: `srv atta2 "<команда>"`
- Текущий Chatwoot: `http://10.3.255.150:3100`
- Docker overlay подход: `Dockerfile.max-overlay` + `docker-compose.max.yml`
- Форк: `https://github.com/aliyaredpilled/chatwoot`, ветка `codex/max-chatwoot-mvp`
- API токен Chatwoot: `R9kA6SJpXbVBacT6u6FhyFqP` (admin@test.local)

### Пересборка после изменений

```bash
srv atta2 "cd ~/chatwoot-max-test && docker build -f Dockerfile.max-overlay -t chatwoot-max:test . && docker compose -f docker-compose.max.yml up -d"
```

### Webhook URL

Для вебхуков Umnico нужен публичный URL. На atta2 есть только внутренний IP.
Варианты:
- Nginx reverse proxy с публичным доменом
- Cloudflare tunnel
- ngrok для тестирования

## Трудности и подводные камни

### 1. Webhook требует публичный URL
Atta2 — внутренний сервер (10.3.255.150). Для вебхуков Umnico нужен URL доступный из интернета.
**Решение:** настроить reverse proxy или tunnel.

### 2. Webhook payload не содержит полное сообщение
Umnico в webhook отправляет только `leadId` и тип события. Тело сообщения нужно
дозапрашивать через `GET /v1.3/leads/<leadId>/messages`.
**Решение:** в IncomingMessageService делать доп. запрос к API.

### 3. Маппинг lead ↔ conversation
В Umnico обращение = lead. Нужно надёжно маппить lead_id на conversation в Chatwoot.
Если юзер пишет из нового канала — Umnico может создать новый lead.
**Решение:** хранить маппинг в `additional_attributes` conversation или в `lead_map` канала.

### 4. Мульти-мессенджер в одном inbox
Один Umnico-канал получает сообщения из Max, Telegram, WhatsApp одновременно.
В Chatwoot нужно как-то показывать откуда пришло сообщение.
**Решение:** сохранять тип мессенджера (`sa.type`) в `additional_attributes` контакта и разговора.

### 5. Формат вложений различается по мессенджерам
При загрузке файлов Umnico возвращает разный формат в зависимости от мессенджера
(VK — media.id, WhatsApp — src, Telegram — fileId).
**Решение:** в api_client унифицировать формат после upload.

### 6. Umnico может отключить webhook
Если наш URL недоступен — Umnico автоматически деактивирует webhook.
**Решение:** мониторинг + периодическая проверка статуса вебхука через API.

### 7. Дубликаты сообщений
Webhook может прийти повторно. Нужна дедупликация по message_id.
**Решение:** проверять `Message.exists?(source_id: ...)` перед созданием (как в Max).

### 8. Версионность API
Umnico API v1.3 — формат может измениться.
**Решение:** зафиксировать версию в base_url клиента.

## Чеклист для MVP

- [ ] Модель Channel::Umnico + миграция
- [ ] Umnico API клиент (auth, send, get messages, upload, webhooks CRUD)
- [ ] Webhook controller + route
- [ ] Incoming message service (с дозапросом тела)
- [ ] Outgoing send service
- [ ] Вложения (входящие + исходящие)
- [ ] Патчи в существующие файлы (inboxes_controller, send_reply_job, account, inbox)
- [ ] Настройка публичного URL для вебхуков
- [ ] Тест полного цикла на atta2
- [ ] Пуш в форк
