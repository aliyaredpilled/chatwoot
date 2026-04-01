class SendReplyJob < ApplicationJob
  queue_as :high

  CHANNEL_SERVICES = {
    'Channel::TwitterProfile' => ::Twitter::SendOnTwitterService,
    'Channel::TwilioSms' => ::Twilio::SendOnTwilioService,
    'Channel::Line' => ::Line::SendOnLineService,
    'Channel::Max' => ::Max::SendOnMaxService,
    'Channel::Umnico' => ::Umnico::SendOnUmnicoService,
    'Channel::Telegram' => ::Telegram::SendOnTelegramService,
    'Channel::Whatsapp' => ::Whatsapp::SendOnWhatsappService,
    'Channel::Sms' => ::Sms::SendOnSmsService,
    'Channel::Instagram' => ::Instagram::SendOnInstagramService,
    'Channel::Tiktok' => ::Tiktok::SendOnTiktokService,
    'Channel::Email' => ::Email::SendOnEmailService,
    'Channel::WebWidget' => ::Messages::SendEmailNotificationService,
    'Channel::Api' => ::Messages::SendEmailNotificationService
  }.freeze

  def perform(message_id)
    message = Message.find(message_id)
    channel_name = message.conversation.inbox.channel.class.to_s

    if channel_name == 'Channel::FacebookPage'
      send_on_facebook_page(message)
      return
    end

    service_class = CHANNEL_SERVICES[channel_name]
    return unless service_class

    service_class.new(message: message).perform
  rescue StandardError => e
    mark_message_as_failed(message, e)
    Rails.logger.error(
      "SendReplyJob failed for message #{message_id} on #{channel_name}: #{e.message}"
    )
  end

  private

  def mark_message_as_failed(message, error)
    return unless message&.persisted?
    return unless message.outgoing? || message.template?
    return if message.failed? && message.external_error.present?

    Messages::StatusUpdateService.new(message, 'failed', error.message).perform
  rescue StandardError => status_error
    Rails.logger.error(
      "SendReplyJob failed to update failed status for message #{message.id}: #{status_error.message}"
    )
  end

  def send_on_facebook_page(message)
    if message.conversation.additional_attributes['type'] == 'instagram_direct_message'
      ::Instagram::Messenger::SendOnInstagramService.new(message: message).perform
    else
      ::Facebook::SendOnFacebookService.new(message: message).perform
    end
  end
end
