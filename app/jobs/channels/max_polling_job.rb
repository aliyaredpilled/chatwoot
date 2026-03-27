class Channels::MaxPollingJob < ApplicationJob
  queue_as :low

  SUPPORTED_UPDATE_TYPES = %w[message_created message_edited message_callback bot_started].freeze

  def perform(channel_id)
    channel = Channel::Max.find_by(id: channel_id)
    return if channel.blank? || !channel.enabled? || !channel.account.active?

    response = channel.api_client.get_updates(
      marker: channel.last_event_marker,
      timeout: channel.polling_interval_seconds,
      limit: 100,
      types: SUPPORTED_UPDATE_TYPES
    )

    response.fetch('updates', []).each do |update|
      Max::IncomingMessageService.new(inbox: channel.inbox, update: normalize_update(update)).perform
    end

    channel.update_columns(last_event_marker: response['marker'], updated_at: Time.current) if response['marker'].present?

    # Re-enqueue self for continuous polling
    self.class.perform_later(channel_id)
  rescue ::Max::ApiClient::Error => e
    Rails.logger.warn("[max] polling failed for channel_id=#{channel_id}: #{e.message}")
    # Re-enqueue with backoff on error
    self.class.set(wait: 10.seconds).perform_later(channel_id)
  end

  private

  def normalize_update(update)
    case update['update_type']
    when 'bot_started'
      {
        'update_type' => 'message_created',
        'message' => {
          'sender' => update['user'],
          'recipient' => { 'chat_id' => update['chat_id'], 'chat_type' => 'dialog' },
          'timestamp' => update['timestamp'],
          'body' => {
            'mid' => "bot_started_#{update['timestamp']}",
            'seq' => update['timestamp'],
            'text' => '/start',
            'attachments' => []
          }
        }
      }
    when 'message_callback'
      callback = update['callback'] || {}
      {
        'update_type' => 'message_created',
        'message' => {
          'sender' => callback['user'],
          'recipient' => update.dig('message', 'recipient') || { 'chat_id' => nil, 'chat_type' => 'dialog' },
          'timestamp' => update['timestamp'],
          'body' => {
            'mid' => "callback_#{callback['callback_id']}",
            'seq' => update['timestamp'],
            'text' => "callback: #{callback['payload']}",
            'attachments' => []
          }
        }
      }
    else
      update
    end
  end
end
