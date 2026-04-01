class Umnico::HistoryBackfillService
  MAX_PAGES = 5

  pattr_initialize [:conversation!, :inbox!]

  def perform
    return if lead_id.blank?

    source_real_id = resolved_source_real_id
    if source_real_id.blank?
      Rails.logger.warn("Umnico: history backfill skipped for conversation #{conversation.id}, source not found for lead #{lead_id}")
      return
    end

    imported_count = 0

    history_messages(source_real_id).sort_by { |message| sort_key(message) }.each do |history_message|
      imported_count += 1 if import_message(history_message)
    end

    Rails.logger.info(
      "Umnico: history backfill imported #{imported_count} messages for conversation #{conversation.id} lead #{lead_id}"
    )
  end

  private

  def lead_id
    conversation.additional_attributes.to_h['lead_id']
  end

  def umnico_source
    conversation.additional_attributes.to_h['umnico_source']
  end

  def channel
    @channel ||= inbox.channel
  end

  def api_client
    @api_client ||= channel.api_client
  end

  def resolved_source_real_id
    return @resolved_source_real_id if defined?(@resolved_source_real_id)
    return umnico_source.to_s if umnico_source.present?

    sources = api_client.get_lead_sources(lead_id)
    source = source_items(sources).find { |item| item['realId'].present? }
    @resolved_source_real_id = source&.dig('realId')&.to_s
  end

  def source_items(sources)
    return sources if sources.is_a?(Array)
    return Array(sources['sources']) if sources.is_a?(Hash)

    []
  end

  def history_messages(source_real_id)
    cursor = nil
    pages_fetched = 0
    messages = []
    seen_cursors = {}

    while pages_fetched < MAX_PAGES
      response = api_client.get_message_history(lead_id, source_real_id, cursor: cursor)
      page_messages = Array(response['messages'])

      messages.concat(page_messages)
      pages_fetched += 1

      next_cursor = response['cursor']
      break if next_cursor.blank? || page_messages.blank?

      cursor_key = next_cursor.to_s
      break if seen_cursors[cursor_key]

      seen_cursors[cursor_key] = true
      cursor = next_cursor
    end

    messages
  end

  def import_message(history_message)
    current_source_id = source_id(history_message)
    return false if current_source_id.blank?
    return false if conversation.messages.exists?(source_id: current_source_id)

    timestamp = message_time(history_message) || Time.current
    message = conversation.messages.build(
      content: message_content(history_message),
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      message_type: history_message['incoming'] ? :incoming : :outgoing,
      sender: message_sender(history_message),
      source_id: current_source_id,
      content_attributes: build_content_attributes(history_message),
      created_at: timestamp,
      updated_at: timestamp
    )

    process_attachments(message, history_message)
    message.save!
    true
  end

  def message_sender(history_message)
    history_message['incoming'] ? conversation.contact : conversation.assignee
  end

  def message_content(history_message)
    body = message_body(history_message)

    body['text'].presence ||
      body['url'].presence ||
      attachment_label(history_message)
  end

  def build_content_attributes(history_message)
    attrs = {
      external_created_at: history_message['datetime'],
      lead_id: lead_id,
      messenger_type: integration_type(history_message)
    }.compact

    reply_to = history_message['replyTo']
    return attrs if reply_to.blank?

    attrs[:reply_to] = reply_to

    in_reply_to = {
      text: reply_to['text'].presence || reply_to.dig('message', 'text').presence,
      sender: reply_to['sender']
    }.compact
    attrs[:in_reply_to] = in_reply_to if in_reply_to.present?

    original = conversation.messages.find_by(source_id: "umnico:#{reply_to['messageId']}")
    attrs[:in_reply_to_external_id] = original.id if original.present?
    attrs
  end

  def process_attachments(message, history_message)
    attachments_meta = []

    message_attachments(history_message).each do |attachment|
      url = attachment.dig('payload', 'url') || attachment['url'] || attachment['src']
      file_type = map_attachment_type(attachment['type'])

      if url.present?
        message.attachments.build(
          account_id: inbox.account_id,
          file_type: file_type,
          external_url: url
        )
      end

      attachments_meta << {
        type: attachment['type'],
        url: url,
        name: attachment['text'].presence,
        filesize: attachment['filesize'],
        preview: attachment['preview'],
        caption: attachment['caption']
      }.compact
    rescue StandardError => e
      Rails.logger.error("Umnico: failed to process backfill attachment for conversation #{conversation.id}: #{e.message}")
    end

    return if attachments_meta.empty?

    message.content_attributes ||= {}
    message.content_attributes['attachments_meta'] = attachments_meta
  end

  def attachment_label(history_message)
    attachments = message_attachments(history_message)
    return '' if attachments.blank?

    first = attachments.first
    first['caption'].presence || first['text'].presence || "[#{first['type'] || 'file'}]"
  end

  def source_id(history_message)
    message_id = history_message['messageId']
    return if message_id.blank?

    "umnico:#{message_id}"
  end

  def message_body(history_message)
    history_message['message'] || {}
  end

  def message_attachments(history_message)
    message_body(history_message)['attachments'] || []
  end

  def integration_type(history_message)
    history_message.dig('sa', 'type') || history_message.dig('sender', 'type')
  end

  def message_time(history_message)
    raw_datetime = history_message['datetime']
    return if raw_datetime.blank?

    if raw_datetime.to_s.match?(/\A\d+\z/)
      Time.zone.at(raw_datetime.to_f / 1000.0)
    else
      Time.zone.parse(raw_datetime.to_s)
    end
  rescue StandardError
    nil
  end

  def sort_key(history_message)
    timestamp = message_time(history_message)
    [timestamp&.to_f || 0, history_message['messageId'].to_s]
  end

  def map_attachment_type(umnico_type)
    case umnico_type
    when 'photo', 'image' then :image
    when 'video' then :video
    when 'audio' then :audio
    when 'sticker' then :image
    else :file
    end
  end
end
