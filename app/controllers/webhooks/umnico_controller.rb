class Webhooks::UmnicoController < ActionController::API
  def process_payload
    Webhooks::UmnicoEventsJob.perform_later(params.to_unsafe_hash.merge('webhook_secret' => params[:webhook_secret]))
    head :ok
  end
end
