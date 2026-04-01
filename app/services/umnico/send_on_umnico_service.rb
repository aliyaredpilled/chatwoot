require 'tempfile'
require 'open-uri'

class Umnico::SendOnUmnicoService < Base::SendOnChannelService
  TEXT_CHUNK_LIMIT = 4_000
  DELIVERY_CONFIRMATION_TIMEOUT = 30.seconds

  private

  def channel_class
    Channel::Umnico
  end

  def perform_reply
    lead_id = resolved_lead_id
    raise ::Umnico::ApiClient::Error, 'Missing lead_id for Umnico outbound message' if lead_id.blank?

    # Set a stable, deterministic source_id immediately so subsequent calls can
    # find this message even if the API call fails partway through.
    message.update!(source_id: "umnico_out_#{message.id}") if message.source_id.blank?

    if message.attachments.any?
      send_attachments(lead_id)
    elsif message.outgoing_content.present?
      send_text_chunks(lead_id)
    end

    mark_delivery_as_pending!
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

  # Returns the numeric Umnico message ID to quote, or nil.
  # Looks at content_attributes['in_reply_to_external_id'], resolves the
  # source_id of that Chatwoot message, and strips the "umnico:" prefix.
  def resolved_reply_id
    @resolved_reply_id ||= compute_reply_id
  end

  def compute_reply_id
    reply_to_id = message.content_attributes&.dig('in_reply_to_external_id')
    return nil if reply_to_id.blank?

    parent = message.conversation.messages.find_by(id: reply_to_id)
    return nil if parent&.source_id.blank?

    raw = parent.source_id.to_s
    # Umnico source_ids look like "umnico:1234567890"
    numeric_str = raw.start_with?('umnico:') ? raw.delete_prefix('umnico:') : raw
    Integer(numeric_str, 10) rescue nil
  end

  def custom_id
    "chatwoot:#{message.id}"
  end

  def delivery_pending_attributes
    (message.content_attributes || {}).merge(
      'umnico_delivery_pending' => true,
      'umnico_delivery_pending_since' => Time.current.iso8601
    ).except('external_error')
  end

  def base_send_opts
    {
      lead_id: resolved_lead_id,
      source: resolved_source,
      user_id: umnico_user_id,
      custom_id: custom_id,
      reply_id: resolved_reply_id
    }
  end

  def send_text_chunks(lead_id)
    chunks = chunk_text(message.outgoing_content.to_s)
    chunks.each_with_index do |chunk, idx|
      # Only attach replyId to the first chunk to avoid quoting repeatedly.
      reply = idx.zero? ? resolved_reply_id : nil
      channel.api_client.send_message(
        **base_send_opts,
        lead_id: lead_id,
        text: chunk,
        reply_id: reply
      )
    end
  end

  def send_attachments(lead_id)
    # Caption text goes with the first attachment only.
    caption = message.outgoing_content.presence
    first = true

    message.attachments.each do |attachment|
      url = attachment.download_url
      next if url.blank?

      type = map_file_type(attachment.file_type)
      media_obj = upload_attachment(attachment, url)

      text_for_this = first ? caption : nil
      first = false

      channel.api_client.send_message(
        **base_send_opts,
        lead_id: lead_id,
        text: text_for_this,
        attachment: { type: type, media: media_obj }
      )
    end
  end

  # Downloads the attachment and uploads it to Umnico.
  # Returns a media hash suitable for the send API.
  # Falls back to a plain { url: } hash if upload fails.
  def upload_attachment(attachment, download_url)
    content_type = attachment.file&.content_type || 'application/octet-stream'
    ext = File.extname(attachment.file&.filename.to_s).presence || ''

    Tempfile.create(['umnico_upload', ext], binmode: true) do |tmp|
      URI.open(download_url, 'rb') { |io| tmp.write(io.read) } # rubocop:disable Security/Open
      tmp.flush

      response = channel.api_client.upload_file(
        source: resolved_source,
        file_path: tmp.path,
        content_type: content_type
      )
      response['media'] || { url: download_url }
    end
  rescue StandardError => e
    Rails.logger.warn("[Umnico] upload_attachment failed (#{e.message}), falling back to URL")
    { url: download_url }
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

  def mark_delivery_as_pending!
    message.update!(content_attributes: delivery_pending_attributes)
    ::Umnico::OutboundDeliveryTimeoutJob
      .set(wait: DELIVERY_CONFIRMATION_TIMEOUT)
      .perform_later(message.id, message.source_id)
  end
end
