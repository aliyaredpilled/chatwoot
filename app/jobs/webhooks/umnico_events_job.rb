class Webhooks::UmnicoEventsJob < ApplicationJob
  queue_as :default

  def perform(params = {})
    webhook_secret = params['webhook_secret']
    return if webhook_secret.blank?

    channel = Channel::Umnico.find_by(webhook_secret: webhook_secret)
    return if channel.blank?
    return unless channel.enabled?
    return unless channel.account.active?

    inbox = channel.inbox
    return if inbox.blank?

    case params['type']
    when 'message.incoming'
      ::Umnico::IncomingMessageService.new(inbox: inbox, params: params).perform
    when 'message.outgoing'
      ::Umnico::OutgoingMessageSyncService.new(inbox: inbox, params: params).perform
    when 'customer.changed', 'customer.created'
      ::Umnico::CustomerSyncService.new(inbox: inbox, params: params).perform
    end
  end
end
