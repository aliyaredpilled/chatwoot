class Umnico::OutgoingMessageSyncService
  pattr_initialize [:inbox!, :params!]

  # Handles message.outgoing events — messages sent from the Umnico UI by operators.
  # Syncs them back into Chatwoot so the conversation history stays complete.

  def perform
    return if lead_id.blank?
    return if webhook_message.blank?
    return if message_id.blank?
    return if sent_from_chatwoot?
    return if duplicate_message?

    conversation = find_conversation
    unless conversation
      Rails.logger.info("Umnico: outgoing message for unknown lead #{lead_id}, skipping")
      return
    end

    create_message(conversation)
  end

  private

  def lead_id
    params['leadId']
  end

  def webhook_message
    @webhook_message ||= params['message'] || {}
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

  # Skip messages that originated from Chatwoot to avoid duplicates.
  # Check both customId (if Umnico echoes it) and existing outgoing messages.
  def sent_from_chatwoot?
    # Method 1: customId set by SendOnUmnicoService
    custom_id = webhook_message['customId'].to_s
    return true if custom_id.start_with?('chatwoot:')

    # Method 2: find a recent outgoing message in this conversation with matching text
    conv = find_conversation
    return false unless conv

    text = message_text
    return false if text.blank?

    conv.messages
      .where(message_type: :outgoing)
      .where('source_id LIKE ?', 'umnico_out_%')
      .where('created_at > ?', 2.minutes.ago)
      .exists?(content: text)
  end

  def duplicate_message?
    Message.exists?(inbox_id: inbox.id, source_id: "umnico:#{message_id}")
  end

  def find_conversation
    inbox.conversations.find_by(
      "additional_attributes->>'lead_id' = ?", lead_id.to_s
    )
  end

  def create_message(conversation)
    content = message_text.presence || attachment_label
    return if content.blank?

    msg = conversation.messages.create!(
      content: content,
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      message_type: :outgoing,
      sender: conversation.assignee,
      source_id: "umnico:#{message_id}",
      content_attributes: {
        external_created_at: webhook_message['datetime'],
        lead_id: lead_id
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
end
