class Api::V1::Accounts::UmnicoController < Api::V1::Accounts::BaseController
  before_action :find_inbox

  # GET /api/v1/accounts/:account_id/umnico/integrations?inbox_id=1
  def integrations
    render json: @inbox.channel.api_client.list_integrations
  end

  # POST /api/v1/accounts/:account_id/umnico/send_outbound
  # { inbox_id: 1, sa_id: 111328, destination: "@username", message: "Hello" }
  def send_outbound
    result = Umnico::OutboundMessageService.new(
      inbox: @inbox,
      sa_id: params[:sa_id],
      destination: params[:destination],
      message_text: params[:message]
    ).perform

    if result[:success]
      render json: result
    else
      render json: { error: result[:error] }, status: :unprocessable_entity
    end
  end

  private

  def find_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id])
    head :not_found unless @inbox.channel.is_a?(Channel::Umnico)
  end
end
