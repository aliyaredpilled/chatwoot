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
  before_validation :fetch_umnico_account_info, on: :create

  validates :api_token, presence: true, uniqueness: true

  after_create_commit :register_umnico_webhook
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

  def fetch_umnico_account_info
    response = api_client.get_account
    self.umnico_account_id = response.dig('account', 'id')
  rescue ::Umnico::ApiClient::Error => e
    errors.add(:api_token, "invalid token: #{e.message}")
  end
end
