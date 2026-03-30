class Umnico::CustomerSyncService
  pattr_initialize [:inbox!, :params!]

  # Handles customer.changed and customer.created events.
  # Fetches fresh customer data from Umnico API and updates the Chatwoot contact.

  def perform
    return if customer_id.blank?

    contact = Contact.find_by(
      account_id: inbox.account_id,
      identifier: "umnico:#{customer_id}"
    )

    unless contact
      Rails.logger.info("Umnico: customer #{customer_id} not found in Chatwoot, skipping sync")
      return
    end

    customer = fetch_customer
    return unless customer.is_a?(Hash)

    update_contact(contact, customer)
  end

  private

  def customer_id
    params['customerId']
  end

  def channel
    @channel ||= inbox.channel
  end

  def fetch_customer
    Umnico::ApiClient.new(api_token: channel.api_token).get_customer(customer_id)
  rescue StandardError => e
    Rails.logger.error("Umnico: failed to fetch customer #{customer_id}: #{e.message}")
    nil
  end

  def update_contact(contact, customer)
    attrs = build_contact_attrs(contact, customer)
    contact.update!(attrs)
  rescue StandardError => e
    Rails.logger.error("Umnico: failed to update contact #{customer_id}: #{e.message}")
  end

  def build_contact_attrs(contact, customer)
    attrs = {}
    attrs[:name] = customer['name'].presence if customer['name'].present?
    attrs[:phone_number] = customer['phone'].presence if customer['phone'].present?
    attrs[:email] = customer['email'].presence if customer['email'].present?
    attrs[:avatar_url] = customer['avatar'].presence if customer['avatar'].present?

    extra = build_additional_attributes(contact, customer)
    attrs[:additional_attributes] = extra if extra.present?

    attrs
  end

  def build_additional_attributes(contact, customer)
    existing = contact.additional_attributes || {}
    merged = existing.merge(
      'address'  => customer['address'].presence,
      'profiles' => customer['profiles'].presence
    ).compact
    merged
  end
end
