# == Schema Information
#
# Table name: channel_max
#
#  id                       :bigint           not null, primary key
#  bot_name                 :string
#  bot_token                :string           not null
#  enabled                  :boolean          default(TRUE), not null
#  last_event_marker        :bigint
#  polling_interval_seconds :integer          default(20), not null
#  user_chat_map            :jsonb            not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  account_id               :integer          not null
#
# Indexes
#
#  index_channel_max_on_bot_token  (bot_token) UNIQUE
#

class Channel::Max < ApplicationRecord
  include Channelable

  self.table_name = 'channel_max'
  EDITABLE_ATTRS = [:bot_token, :enabled, :polling_interval_seconds].freeze

  encrypts :bot_token, deterministic: true if Chatwoot.encryption_configured?

  before_validation :ensure_valid_bot_token, on: :create

  validates :bot_token, presence: true, uniqueness: true
  validates :polling_interval_seconds, numericality: { greater_than_or_equal_to: 5, less_than_or_equal_to: 50 }

  scope :active, -> { where(enabled: true) }

  def name
    'Max'
  end

  def api_client
    ::Max::ApiClient.new(bot_token: bot_token)
  end

  def send_message_on_max(message)
    ::Max::SendOnMaxService.new(message: message).perform
  end

  def remember_chat_mapping!(user_id:, chat_id:)
    return if user_id.blank? || chat_id.blank?

    update_columns(
      user_chat_map: (user_chat_map || {}).merge(user_id.to_s => chat_id),
      updated_at: Time.current
    )
  end

  def resolve_chat_id(user_id:, fallback_chat_id: nil)
    (user_chat_map || {})[user_id.to_s].presence || fallback_chat_id
  end

  private

  def ensure_valid_bot_token
    response = api_client.get_me
    self.bot_name = response['name'] || response['username']
  rescue ::Max::ApiClient::Error
    errors.add(:bot_token, 'invalid token')
  end
end
