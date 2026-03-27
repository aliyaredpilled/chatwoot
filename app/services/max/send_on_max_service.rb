class Max::SendOnMaxService < Base::SendOnChannelService
  TEXT_CHUNK_LIMIT = 4_000

  private

  def channel_class
    Channel::Max
  end

  def perform_reply
    target_chat_id = resolved_chat_id
    raise ::Max::ApiClient::Error, 'Missing chat_id for Max outbound message' if target_chat_id.blank?

    chunk_text(message.outgoing_content.to_s).each do |chunk|
      channel.api_client.send_message(
        chat_id: target_chat_id,
        text: normalize_markdown(chunk),
        format: 'markdown'
      )
    end

    message.update!(source_id: "max_out_#{Time.current.to_i}") if message.source_id.blank?
  end

  def resolved_chat_id
    attrs = message.conversation.additional_attributes || {}
    sender_id = attrs['sender_id']
    fallback_chat_id = attrs['chat_id']
    channel.resolve_chat_id(user_id: sender_id, fallback_chat_id: fallback_chat_id)
  end

  def normalize_markdown(text)
    text.gsub(/```\w*\n/, "```\n")
  end

  def chunk_text(text)
    return [text] if text.length <= TEXT_CHUNK_LIMIT

    chunks = []
    remaining = text.dup

    while remaining.present?
      if remaining.length <= TEXT_CHUNK_LIMIT
        chunks << remaining
        break
      end

      split_at = remaining.rindex("\n", TEXT_CHUNK_LIMIT) || TEXT_CHUNK_LIMIT
      split_at = TEXT_CHUNK_LIMIT if split_at < (TEXT_CHUNK_LIMIT * 0.3)
      chunks << remaining[0...split_at]
      remaining = remaining[split_at..].to_s.lstrip
    end

    chunks
  end
end
