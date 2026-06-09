class Api::V1::Billing::WebhooksController < ActionController::API
  def stripe
    payload = request.body.read
    sig_header = request.headers['Stripe-Signature']

    begin
      event = Stripe::Webhook.construct_event(
        payload,
        sig_header,
        ENV.fetch('STRIPE_WEBHOOK_SECRET', nil)
      )

      Billing::StripeWebhookService.new.perform(event)
      head :ok
    rescue JSON::ParserError, Stripe::SignatureVerificationError => e
      Rails.logger.error "[Stripe Webhook Error] #{e.message}"
      head :bad_request
    rescue StandardError => e
      Rails.logger.error "[Stripe Webhook Processing Error] #{e.message}"
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end
end
