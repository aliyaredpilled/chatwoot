class Umnico::SendOnUmnicoService < Base::SendOnChannelService
  TEXT_CHUNK_LIMIT = 4_000

  private

  def channel_class
    Channel::Umnico
  end

  def perform_reply
    lead_id = resolved_lead_id
    raise ::Umnico::ApiClient::Error, 'Missing lead_id for Umnico outbound message' if lead_id.blank?

    send_text_chunks(lead_id) if message.outgoing_content.present?
    send_attachments(lead_id) if message.attachments.any?

    message.update!(source_id: "umnico_out_#{Time.current.to_i}") if message.source_id.blank?
  end

  def conversation_attrs
    @conversation_attrs ||= message.conversation.additional_attributes || {}
  end

  def resolved_lead_id
    conversation_attrs['lead_id']
  end

  def resolved_source
    conversation_attrs['umnico_source']
  end

  def umnico_user_id
    @umnico_user_id ||= begin
      managers = channel.api_client.get_managers
      owner = managers.find { |m| m['role'] == 'owner' } || managers.first
      owner&.dig('id')
    end
  end

  def send_text_chunks(lead_id)
    chunk_text(message.outgoing_content.to_s).each do |chunk|
      channel.api_client.send_message(lead_id: lead_id, text: chunk, source: resolved_source, user_id: umnico_user_id)
    end
  end

  def send_attachments(lead_id)
    message.attachments.each do |attachment|
      url = attachment.download_url
      next if url.blank?

      type = map_file_type(attachment.file_type)
      channel.api_client.send_message(
        lead_id: lead_id,
        source: resolved_source,
        user_id: umnico_user_id,
        attachment: {
          type: type,
          media: { url: url }
        }
      )
    end
  end

  def map_file_type(chatwoot_type)
    case chatwoot_type.to_s
    when 'image'  then 'photo'
    when 'video'  then 'video'
    when 'audio'  then 'audio'
    else 'doc'
    end
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
