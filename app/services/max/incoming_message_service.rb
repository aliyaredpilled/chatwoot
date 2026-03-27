class Max::IncomingMessageService
  pattr_initialize [:inbox!, :update!]

  def perform
    return if message.blank?
    return unless direct_message?
    return if sender.blank? || body.blank?
    return if sender['is_bot']
    return if body['mid'].blank?
    return if Message.exists?(inbox_id: inbox.id, source_id: body['mid'].to_s)

    set_contact
    set_conversation
    remember_chat_mapping
    create_message
  end

  private

  def message
    @message ||= update['message'] || {}
  end

  def sender
    @sender ||= message['sender'] || {}
  end

  def body
    @body ||= message['body'] || {}
  end

  def recipient
    @recipient ||= message['recipient'] || {}
  end

  def direct_message?
    recipient['chat_type'] == 'dialog'
  end

  def sender_id
    sender['user_id']
  end

  def chat_id
    recipient['chat_id']
  end

  def source_id
    "max:#{sender_id}"
  end

  def set_contact
    contact_inbox = ::ContactInboxWithContactBuilder.new(
      source_id: source_id,
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
        chat_id: chat_id,
        sender_id: sender_id,
        provider: 'max'
      }.compact
    }
  end

  def create_message
    @conversation.messages.create!(
      content: message_content,
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      message_type: :incoming,
      sender: @contact,
      source_id: body['mid'].to_s,
      content_attributes: {
        external_created_at: message['timestamp'],
        chat_id: chat_id,
        sender_id: sender_id
      }.compact
    )
  end

  def remember_chat_mapping
    inbox.channel.remember_chat_mapping!(user_id: sender_id, chat_id: chat_id)
  end

  def message_content
    [reply_context, body['text'].to_s].reject(&:blank?).join("\n\n")
  end

  def reply_context
    linked_message = message['link'] || {}
    return if linked_message['type'] != 'reply'

    reply_sender = linked_message.dig('sender', 'name').presence || 'unknown'
    reply_text = linked_message.dig('message', 'text').presence || '<media>'
    "[Replying to #{reply_sender}]\n#{reply_text}"
  end

  def contact_attributes
    {
      name: sender['name'].presence || sender['username'].presence || "Max #{sender_id}",
      identifier: source_id,
      additional_attributes: {
        provider: 'max',
        social_max_user_id: sender_id,
        social_max_username: sender['username']
      }.compact
    }
  end
end
