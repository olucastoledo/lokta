class Billing::StripeBillingService
  def initialize(account)
    @account = account
    Stripe.api_key = ENV.fetch('STRIPE_SECRET_KEY', nil)
  end

  def create_checkout_session(price_id)
    subscription = Billing::Subscription.find_or_initialize_by(account_id: @account.id)

    customer_id = subscription.stripe_customer_id
    if customer_id.blank?
      billing_email = @account.support_email.presence || @account.administrators.first&.email
      customer = Stripe::Customer.create(
        name: @account.name,
        email: billing_email,
        metadata: { account_id: @account.id }
      )
      customer_id = customer.id
      subscription.update!(stripe_customer_id: customer_id)
    end

    frontend_host = ENV.fetch('FRONTEND_URL', 'localhost:3000')
    protocol = frontend_host.start_with?('http') ? '' : 'https://'
    success_url = ENV['STRIPE_CHECKOUT_SUCCESS_URL'] || "#{protocol}#{frontend_host}/app/accounts/#{@account.id}/settings/billing?session_id={CHECKOUT_SESSION_ID}"
    cancel_url = ENV['STRIPE_CHECKOUT_CANCEL_URL'] || "#{protocol}#{frontend_host}/app/accounts/#{@account.id}/settings/billing"

    session = Stripe::Checkout::Session.create({
                                                 customer: customer_id,
                                                 payment_method_types: ['card'],
                                                 line_items: [{
                                                   price: price_id,
                                                   quantity: 1
                                                 }],
                                                 mode: 'subscription',
                                                 success_url: success_url,
                                                 cancel_url: cancel_url,
                                                 subscription_data: {
                                                   metadata: { account_id: @account.id }
                                                 },
                                                 metadata: { account_id: @account.id }
                                               })

    session.url
  end

  def create_portal_session
    subscription = Billing::Subscription.find_by!(account_id: @account.id)
    customer_id = subscription.stripe_customer_id
    raise 'Nenhum cliente Stripe configurado para esta conta.' if customer_id.blank?

    frontend_host = ENV.fetch('FRONTEND_URL', 'localhost:3000')
    protocol = frontend_host.start_with?('http') ? '' : 'https://'
    return_url = ENV['STRIPE_CUSTOMER_PORTAL_RETURN_URL'] || "#{protocol}#{frontend_host}/app/accounts/#{@account.id}/settings/billing"

    session = Stripe::BillingPortal::Session.create({
                                                      customer: customer_id,
                                                      return_url: return_url
                                                    })

    session.url
  end

  def sync_subscription(stripe_sub_id = nil)
    subscription = Billing::Subscription.find_or_initialize_by(account_id: @account.id)
    sub_id = stripe_sub_id || subscription.stripe_subscription_id
    return false if sub_id.blank?

    stripe_sub = Stripe::Subscription.retrieve(sub_id)
    price = stripe_sub['items']['data'].first['price']
    product_id = price['product']
    price_id = price['id']
    amount = price['unit_amount'] ? (price['unit_amount'] / 100.0) : 0.0
    currency = price['currency']

    plan_name = begin
      Stripe::Product.retrieve(product_id)['name']
    rescue StandardError
      'Plano Customizado'
    end

    subscription.update!(
      stripe_subscription_id: stripe_sub.id,
      stripe_customer_id: stripe_sub.customer,
      stripe_price_id: price_id,
      stripe_product_id: product_id,
      plan_name: plan_name,
      amount: amount,
      currency: currency,
      status: stripe_sub.status,
      current_period_start: Time.zone.at(stripe_sub.current_period_start),
      current_period_end: Time.zone.at(stripe_sub.current_period_end),
      trial_end: stripe_sub.trial_end ? Time.zone.at(stripe_sub.trial_end) : nil,
      next_payment_at: Time.zone.at(stripe_sub.current_period_end),
      last_payment_at: Time.zone.now
    )

    if subscription.blocked?
      subscription.update!(blocked_at: subscription.blocked_at || Time.zone.now)
    else
      subscription.update!(blocked_at: nil)
    end

    # Auditar evento
    Billing::Event.create!(
      account_id: @account.id,
      event_type: 'subscription_sync',
      description: "Assinatura sincronizada com Stripe. Novo status: #{subscription.status}."
    )

    true
  end
end
