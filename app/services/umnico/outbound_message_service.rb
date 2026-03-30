class Umnico::OutboundMessageService
  pattr_initialize [:inbox!, :sa_id!, :destination!, :message_text!]

  def perform
    channel = inbox.channel
    client = Umnico::ApiClient.new(api_token: channel.api_token)

    response = client.send_outbound_message(
      sa_id: sa_id,
      destination: destination,
      text: message_text
    )

    { success: true, response: response }
  rescue Umnico::ApiClient::Error => e
    { success: false, error: e.message }
  end
end
