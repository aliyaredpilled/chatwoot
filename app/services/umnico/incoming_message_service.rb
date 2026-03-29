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
    @conversation = if inbox.lock_to_single_conversation
                      @contact_inbox.conversations.last
                    else
                      @contact_inbox.conversations.where.not(status: :resolved).last
                    end
    return if @conversation

    @conversation = ::Conversation.create!(conversation_params)
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
      content_attributes: {
        external_created_at: webhook_message['datetime'],
        lead_id: lead_id,
        messenger_type: integration_type
      }.compact
    )

    process_attachments(msg)
    msg
  end

  def attachment_label
    return '' if message_attachments.blank?

    first = message_attachments.first
    type = first['type'] || 'file'
    "[#{type}]"
  end

  def process_attachments(msg)
    message_attachments.each do |att|
      url = att.dig('payload', 'url') || att['url'] || att['src']
      next if url.blank?

      file_type = map_attachment_type(att['type'])

      msg.attachments.create!(
        account_id: inbox.account_id,
        file_type: file_type,
        external_url: url
      )
    rescue StandardError => e
      Rails.logger.error("Umnico: failed to process attachment: #{e.message}")
    end
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
    {
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
  end
end
