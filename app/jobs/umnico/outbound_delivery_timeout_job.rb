class Umnico::OutboundDeliveryTimeoutJob < ApplicationJob
  queue_as :low

  ERROR_MESSAGE = 'Umnico did not confirm outgoing delivery'.freeze

  def perform(message_id, expected_source_id = nil)
    message = Message.find_by(id: message_id)
    return if message.blank?
    return unless message.inbox.channel.is_a?(Channel::Umnico)
    return unless message.outgoing? || message.template?
    return if expected_source_id.present? && message.source_id != expected_source_id

    content_attributes = message.content_attributes || {}
    return unless content_attributes['umnico_delivery_pending']

    message.update!(
      status: :failed,
      content_attributes: timeout_content_attributes(content_attributes)
    )
  end

  private

  def timeout_content_attributes(content_attributes)
    content_attributes
      .except('umnico_delivery_pending', 'umnico_delivery_pending_since')
      .merge('external_error' => ERROR_MESSAGE)
  end
end
