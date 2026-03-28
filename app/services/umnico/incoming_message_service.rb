class Umnico::IncomingMessageService
  pattr_initialize [:inbox!, :params!]

  def perform
    return unless params['type'] == 'message.incoming'
    return if lead_id.blank?

    # Webhook может содержать message объект, но для контакта нужен lead
    fetch_lead_details
    return if @lead.blank?

    # Используем message из webhook если есть, иначе из lead
    @message_data = params['message'] || extract_last_message_from_lead
    return if @message_data.blank?
    return if duplicate_message?

    set_contact
    set_conversation
    create_message
  end

  private

  def lead_id
    params['leadId']
  end

  def fetch_lead_details
    @lead = channel.api_client.get_lead(lead_id)
  rescue ::Umnico::ApiClient::Error => e
    Rails.logger.error("Umnico: failed to fetch lead #{lead_id}: #{e.message}")
    @lead = nil
  end

  def extract_last_message_from_lead
    # Lead response contains lastMessage or similar
    @lead['lastMessage'] || @lead['message']
  end

  def duplicate_message?
    msg_id = @message_data['id']&.to_s
    return true if msg_id.blank?

    Message.exists?(inbox_id: inbox.id, source_id: "umnico:#{msg_id}")
  end

  def channel
    @channel ||= inbox.channel
  end

  def customer
    @customer ||= @lead['customer'] || {}
  end

  def integration_type
    @lead.dig('sa', 'type') || 'unknown'
  end

  def contact_source_id
    "umnico:#{customer['id']}"
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
        provider: 'umnico',
        messenger_type: integration_type
      }.compact
    }
  end

  def create_message
    text = @message_data['text'].to_s
    attachment_data = @message_data['attachment']

    msg = @conversation.messages.create!(
      content: text.presence || attachment_label(attachment_data),
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      message_type: :incoming,
      sender: @contact,
      source_id: "umnico:#{@message_data['id']}",
      content_attributes: {
        external_created_at: @message_data['datetime'] || @message_data['createdAt'],
        lead_id: lead_id,
        messenger_type: integration_type
      }.compact
    )

    process_attachments(msg, attachment_data) if attachment_data.present?
    msg
  end

  def attachment_label(attachment_data)
    return '' if attachment_data.blank?

    type = attachment_data['type'] || 'file'
    "[#{type}]"
  end

  def process_attachments(msg, attachment_data)
    return if attachment_data.blank?

    url = attachment_data.dig('media', 'url') || attachment_data['src'] || attachment_data['url']
    return if url.blank?

    file_type = map_attachment_type(attachment_data['type'])

    msg.attachments.create!(
      account_id: inbox.account_id,
      file_type: file_type,
      external_url: url
    )
  rescue StandardError => e
    Rails.logger.error("Umnico: failed to process attachment: #{e.message}")
  end

  def map_attachment_type(umnico_type)
    case umnico_type
    when 'photo'   then :image
    when 'video'   then :video
    when 'audio'   then :audio
    when 'sticker' then :image
    else :file
    end
  end

  def contact_attributes
    name = customer['name'].presence || customer['phone'].presence || "Umnico #{customer['id']}"
    {
      name: name,
      identifier: contact_source_id,
      phone_number: customer['phone'],
      additional_attributes: {
        provider: 'umnico',
        umnico_customer_id: customer['id'],
        messenger_type: integration_type
      }.compact
    }
  end
end
