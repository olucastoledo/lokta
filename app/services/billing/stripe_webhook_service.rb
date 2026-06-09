class Billing::StripeWebhookService
  def perform(event)
    @event = event
    @object = event.data.object

    case event.type
    when 'checkout.session.completed'
      handle_checkout_session_completed
    when 'customer.subscription.created', 'customer.subscription.updated'
      handle_subscription_updated
    when 'customer.subscription.deleted'
      handle_subscription_deleted
    when 'invoice.created', 'invoice.finalized'
      handle_invoice_created
    when 'invoice.paid'
      handle_invoice_paid
    when 'invoice.payment_failed', 'invoice.payment_action_required'
      handle_invoice_payment_failed
    end

    trigger_n8n_webhook
  end

  private

  def find_account_by_stripe_customer_id(customer_id)
    sub = Billing::Subscription.find_by(stripe_customer_id: customer_id)
    return sub.account if sub.present?

    Account.where("custom_attributes->>'stripe_customer_id' = ?", customer_id).first
  end

  def handle_checkout_session_completed
    account_id = @object.metadata&.account_id || @object.subscription_data&.metadata&.account_id
    account = Account.find_by(id: account_id) if account_id.present?
    account ||= find_account_by_stripe_customer_id(@object.customer)
    return if account.blank?

    subscription = Billing::Subscription.find_or_initialize_by(account_id: account.id)
    subscription.update!(
      stripe_customer_id: @object.customer,
      stripe_subscription_id: @object.subscription
    )

    Billing::StripeBillingService.new(account).sync_subscription(@object.subscription)
  end

  def handle_subscription_updated
    customer_id = @object.customer
    account = find_account_by_stripe_customer_id(customer_id)
    return if account.blank?

    Billing::StripeBillingService.new(account).sync_subscription(@object.id)
  end

  def handle_subscription_deleted
    customer_id = @object.customer
    account = find_account_by_stripe_customer_id(customer_id)
    return if account.blank?

    subscription = Billing::Subscription.find_or_initialize_by(account_id: account.id)
    subscription.update!(
      status: 'canceled',
      cancellation_at: Time.zone.now,
      blocked_at: Time.zone.now
    )

    Billing::Event.create!(
      account_id: account.id,
      event_type: 'subscription_deleted',
      description: 'Assinatura Stripe cancelada. Acesso à workspace bloqueado.'
    )
  end

  def handle_invoice_created
    customer_id = @object.customer
    account = find_account_by_stripe_customer_id(customer_id)
    return if account.blank?

    amount = @object.amount_due ? (@object.amount_due / 100.0) : 0.0
    invoice = Billing::Invoice.find_or_initialize_by(stripe_invoice_id: @object.id)
    invoice.update!(
      account_id: account.id,
      stripe_customer_id: customer_id,
      stripe_subscription_id: @object.subscription,
      amount: amount,
      currency: @object.currency,
      status: @object.status || 'open',
      invoice_url: @object.hosted_invoice_url,
      invoice_pdf: @object.invoice_pdf
    )

    Billing::Event.create!(
      account_id: account.id,
      event_type: 'invoice_created',
      description: "Nova fatura criada: #{@object.id}. Valor: #{amount} #{invoice.currency.upcase}."
    )
  end

  def handle_invoice_paid
    customer_id = @object.customer
    account = find_account_by_stripe_customer_id(customer_id)
    return if account.blank?

    amount = @object.amount_paid ? (@object.amount_paid / 100.0) : 0.0
    invoice = Billing::Invoice.find_or_initialize_by(stripe_invoice_id: @object.id)
    invoice.update!(
      account_id: account.id,
      stripe_customer_id: customer_id,
      stripe_subscription_id: @object.subscription,
      amount: amount,
      currency: @object.currency,
      status: 'paid',
      invoice_url: @object.hosted_invoice_url,
      invoice_pdf: @object.invoice_pdf
    )

    subscription = Billing::Subscription.find_or_initialize_by(account_id: account.id)
    subscription.update!(status: 'active', blocked_at: nil)

    Billing::Event.create!(
      account_id: account.id,
      event_type: 'invoice_paid',
      description: "Fatura paga com sucesso: #{@object.id}. Assinatura liberada."
    )
  end

  def handle_invoice_payment_failed
    customer_id = @object.customer
    account = find_account_by_stripe_customer_id(customer_id)
    return if account.blank?

    invoice = Billing::Invoice.find_or_initialize_by(stripe_invoice_id: @object.id)
    invoice.update!(status: 'unpaid')

    subscription = Billing::Subscription.find_or_initialize_by(account_id: account.id)
    subscription.update!(status: 'past_due', blocked_at: Time.zone.now)

    Billing::Event.create!(
      account_id: account.id,
      event_type: 'invoice_payment_failed',
      description: "Falha de pagamento na fatura: #{@object.id}. Assinatura bloqueada."
    )
  end

  def trigger_n8n_webhook
    n8n_url = ENV.fetch('N8N_BILLING_WEBHOOK_URL', nil)
    return if n8n_url.blank?

    account = find_account_by_stripe_customer_id(@object.customer)
    Thread.new do
      HTTParty.post(
        n8n_url,
        body: {
          event_type: @event.type,
          account_id: account&.id,
          account_name: account&.name,
          stripe_customer_id: @object.customer,
          object: @object
        }.to_json,
        headers: { 'Content-Type' => 'application/json' },
        timeout: 5
      )
    rescue StandardError => e
      Rails.logger.error "[Billing n8n Webhook] Error calling n8n: #{e.message}"
    end
  end
end
