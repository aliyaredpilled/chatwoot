class Umnico::IncomingMessageService
  pattr_initialize [:inbox!, :params!]

  # Real webhook payload for message.incoming:
  # {
  #   "type": "message.incoming",
  #   "accountId": 162545,
  #   "leadId": 64951289,
  #   "isNewLead": true,
  #   "isNewCustomer": true,
  #   "message": {
  #     "messageId": 11070,
  #     "datetime": "2026-03-29T00:55:07.000Z",
  #     "sa": { "id": 111328, "type": "telegram", "login": "skynet_kazan_support" },
  #     "message": { "text": "привет", "attachments": [] },
  #     "incoming": true,
  #     "sender": {
  #       "id": 65070946, "customerId": 69524567,
  #       "login": "aliya_arkhangelsk", "type": "telegram",
  #       "socialId": "user_647960541", "profileUrl": "https://t.me/aliya_arkhangelsk"
  #     },
  #     "source": { "id": "user_7715692646", "realId": 76919905, "saId": 111328 },
  #     "replyTo": nil
  #   }
  # }

  def perform
    return unless params['type'] == 'message.incoming'
    return if lead_id.blank?
    return if webhook_message.blank?
    return if message_id.blank?
    return if duplicate_message?

    set_contact
    set_conversation
    create_message
    enqueue_history_backfill if history_backfill_required?
  end

  private

  def lead_id
    params['leadId']
  end

  def webhook_message
    @webhook_message ||= params['message'] || {}
  end

  def sender
    @sender ||= webhook_message['sender'] || {}
  end

  def sa
    @sa ||= webhook_message['sa'] || {}
  end

  def message_body
    @message_body ||= webhook_message['message'] || {}
  end

  def message_id
    webhook_message['messageId']
  end

  def message_text
    message_body['text'].to_s
  end

  def message_attachments
    message_body['attachments'] || []
  end

  def integration_type
    sa['type'] || sender['type'] || 'unknown'
  end

  def customer_id
    sender['customerId']
  end

  def contact_source_id
    "umnico:#{customer_id}"
  end

  def duplicate_message?
    Message.exists?(inbox_id: inbox.id, source_id: "umnico:#{message_id}")
  end

  def channel
    @channel ||= inbox.channel
  end

  def set_contact
    contact_inbox = ::ContactInboxWithContactBuilder.new(
      source_id: contact_source_id,
      inbox: inbox,
      contact_attributes: contact_attributes
    ).perform

    @contact_inbox = contact_inbox
    @contact = contact_inbox.contact
  end

  def set_conversation
    @conversation_created = false
    @conversation = if inbox.lock_to_single_conversation
                      @contact_inbox.conversations.last
                    else
                      @contact_inbox.conversations.where.not(status: :resolved).last
                    end
    unless @conversation
      @conversation = ::Conversation.create!(conversation_params)
      @conversation_created = true
    end
    apply_messenger_label
    enrich_conversation_from_lead
  end

  def enqueue_history_backfill
    conv = @conversation
    ib = inbox
    Thread.new do
      ::Umnico::HistoryBackfillService.new(conversation: conv, inbox: ib).perform
    rescue StandardError => e
      Rails.logger.warn("Umnico: history backfill failed for conversation #{conv.id}: #{e.message}")
    end
  end

  def history_backfill_required?
    params['isNewLead'] == true || @conversation_created == true
  end

  def apply_messenger_label
    label_name = messenger_label_name
    return if label_name.blank?

    label = label_name.downcase
    current = @conversation.label_list || []
    return if current.include?(label)

    @conversation.update!(label_list: (current + [label]).uniq)
  end

  def enrich_conversation_from_lead
    return unless params['isNewLead'] == true

    client = api_client
    lead = client.get_lead(lead_id)
    return unless lead.is_a?(Hash)

    attrs = {}

    attrs[:umnico_status]  = lead['statusId']  if lead['statusId'].present?
    attrs[:umnico_tags]    = lead['tags']       if lead['tags'].is_a?(Array) && lead['tags'].any?
    attrs[:umnico_details] = lead['details']    if lead['details'].present?
    attrs[:umnico_amount]  = lead['amount']     if lead['amount'].present?

    custom_fields = lead['customFields']
    if custom_fields.is_a?(Hash)
      custom_fields.each do |key, value|
        field_value = value.is_a?(Hash) ? value['value'] : value
        attrs["cf_#{key}"] = field_value if field_value.present?
      end
    end

    items = lead['items']
    attrs[:umnico_items] = items if items.is_a?(Array) && items.any?

    return if attrs.empty?

    existing = @conversation.custom_attributes || {}
    @conversation.update!(custom_attributes: existing.merge(attrs.stringify_keys))
  rescue StandardError => e
    Rails.logger.warn("Umnico: failed to enrich conversation #{lead_id} from lead: #{e.message}")
  end

  MESSENGER_LABELS = {
    'max' => 'Max',
    'ok' => 'Max',
    'telebot' => 'Telegram',
    'telegram' => 'Telegram',
    'whatsapp2' => 'WhatsApp',
    'waba' => 'WhatsApp',
    'vk_group' => 'VK',
    'viber_bot' => 'Viber',
    'discord' => 'Discord',
    'fb_messenger' => 'Facebook',
    'instagramV3' => 'Instagram'
  }.freeze

  def messenger_label_name
    MESSENGER_LABELS[integration_type]
  end

  def conversation_params
    {
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      contact_id: @contact.id,
      contact_inbox_id: @contact_inbox.id,
      additional_attributes: {
        lead_id: lead_id,
        umnico_source: webhook_message.dig('source', 'realId')&.to_s,
        provider: 'umnico',
        messenger_type: integration_type
      }.compact
    }
  end

  def create_message
    content = message_text.presence || attachment_label
    return if content.blank?

    msg = @conversation.messages.create!(
      content: content,
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      message_type: :incoming,
      sender: @contact,
      source_id: "umnico:#{message_id}",
      content_attributes: build_content_attributes
    )

    process_attachments(msg)
    msg
  end

  def build_content_attributes
    attrs = {
      external_created_at: webhook_message['datetime'],
      lead_id: lead_id,
      messenger_type: integration_type
    }

    reply_to = webhook_message['replyTo']
    if reply_to.present?
      in_reply_to = {
        text: reply_to['text'].presence,
        sender: reply_to['sender']
      }.compact
      attrs[:in_reply_to] = in_reply_to

      original = Message.find_by(
        inbox_id: inbox.id,
        source_id: "umnico:#{reply_to['messageId']}"
      )
      attrs[:in_reply_to_external_id] = original.id if original
    end

    attrs.compact
  end

  def attachment_label
    return '' if message_attachments.blank?

    first = message_attachments.first
    caption = message_body['caption'].presence || first['caption'].presence
    type = first['type'] || 'file'
    caption.presence || "[#{type}]"
  end

  def process_attachments(msg)
    attachments_meta = []

    message_attachments.each do |att|
      url = att.dig('payload', 'url') || att['url'] || att['src']
      next if url.blank?

      file_type = map_attachment_type(att['type'])

      msg.attachments.create!(
        account_id: inbox.account_id,
        file_type: file_type,
        external_url: url
      )

      attachments_meta << {
        type: att['type'],
        url: url,
        name: att['text'].presence,
        filesize: att['filesize'],
        preview: att['preview']
      }.compact
    rescue StandardError => e
      Rails.logger.error("Umnico: failed to process attachment: #{e.message}")
    end

    return if attachments_meta.empty?

    existing = msg.content_attributes || {}
    msg.update_columns(content_attributes: existing.merge('attachments_meta' => attachments_meta))
  end

  def map_attachment_type(umnico_type)
    case umnico_type
    when 'photo', 'image' then :image
    when 'video'          then :video
    when 'audio'          then :audio
    when 'sticker'        then :image
    else :file
    end
  end

  def contact_attributes
    name = sender['login'].presence || sender['name'].presence || "Umnico #{customer_id}"
    attrs = {
      name: name,
      identifier: contact_source_id,
      additional_attributes: {
        provider: 'umnico',
        umnico_customer_id: customer_id,
        messenger_type: integration_type,
        social_id: sender['socialId'],
        profile_url: sender['profileUrl']
      }.compact
    }

    # Enrich with data from Umnico customer API
    enrich_from_umnico(attrs)
  end

  def api_client
    @api_client ||= Umnico::ApiClient.new(api_token: channel.api_token)
  end

  def enrich_from_umnico(attrs)
    return attrs if customer_id.blank?

    client = api_client
    customer = client.get_customer(customer_id)
    return attrs unless customer.is_a?(Hash)

    attrs[:name] = customer['name'].presence || attrs[:name]
    attrs[:phone_number] = customer['phone'].presence
    attrs[:email] = customer['email'].presence
    attrs[:avatar_url] = customer['avatar'].presence

    attrs[:additional_attributes][:address] = customer['address'].presence if customer['address'].present?

    profiles = customer['profiles']
    attrs[:additional_attributes][:profiles] = profiles if profiles.is_a?(Array) && profiles.any?

    attrs
  rescue StandardError => e
    Rails.logger.warn("Umnico: failed to enrich contact #{customer_id}: #{e.message}")
    attrs
  end
end
