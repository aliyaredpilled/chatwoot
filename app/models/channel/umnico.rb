# == Schema Information
#
# Table name: channel_umnico
#
#  id                :bigint           not null, primary key
#  api_token         :string           not null
#  webhook_secret    :string
#  webhook_id        :string
#  umnico_account_id :integer
#  enabled           :boolean          default(TRUE), not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :integer          not null
#
# Indexes
#
#  index_channel_umnico_on_api_token  (api_token) UNIQUE
#

class Channel::Umnico < ApplicationRecord
  include Channelable

  self.table_name = 'channel_umnico'
  EDITABLE_ATTRS = [:api_token, :enabled].freeze

  encrypts :api_token, deterministic: true if Chatwoot.encryption_configured?

  before_validation :generate_webhook_secret, on: :create
  before_validation :fetch_umnico_account_info, if: :should_refresh_umnico_account_info?

  validates :api_token, presence: true, uniqueness: true

  after_create_commit :register_umnico_webhook
  after_update_commit :refresh_umnico_webhook, if: :saved_change_to_api_token?
  before_destroy :unregister_umnico_webhook

  scope :active, -> { where(enabled: true) }

  def name
    'Umnico'
  end

  def api_client
    ::Umnico::ApiClient.new(api_token: api_token)
  end

  def send_message_on_umnico(message)
    ::Umnico::SendOnUmnicoService.new(message: message).perform
  end

  private

  def should_refresh_umnico_account_info?
    will_save_change_to_api_token?
  end

  def generate_webhook_secret
    self.webhook_secret ||= SecureRandom.hex(20)
  end

  def register_umnico_webhook
    webhook_url = "#{ENV.fetch('FRONTEND_URL', nil)}/webhooks/umnico/#{webhook_secret}"
    response = api_client.create_webhook(url: webhook_url, name: "chatwoot-#{id}")
    update_columns(webhook_id: response['id'].to_s) if response['id'].present?
  rescue ::Umnico::ApiClient::Error => e
    Rails.logger.error("Umnico: failed to register webhook: #{e.message}")
  end

  def unregister_umnico_webhook
    return if webhook_id.blank?

    api_client.delete_webhook(webhook_id)
  rescue ::Umnico::ApiClient::Error => e
    Rails.logger.error("Umnico: failed to delete webhook #{webhook_id}: #{e.message}")
  end

  def refresh_umnico_webhook
    unregister_previous_webhook
    register_umnico_webhook
  end

  def unregister_previous_webhook
    previous_webhook_id = webhook_id_before_last_save.presence
    previous_token = api_token_before_last_save.presence
    return if previous_webhook_id.blank? || previous_token.blank?

    ::Umnico::ApiClient
      .new(api_token: previous_token)
      .delete_webhook(previous_webhook_id)
  rescue ::Umnico::ApiClient::Error => e
    Rails.logger.error(
      "Umnico: failed to delete previous webhook #{previous_webhook_id}: #{e.message}"
    )
  end

  def fetch_umnico_account_info
    return if api_token.blank?

    response = api_client.get_account
    self.umnico_account_id = response.dig('account', 'id')
  rescue ::Umnico::ApiClient::Error => e
    errors.add(:api_token, "invalid token: #{e.message}")
  end
end
