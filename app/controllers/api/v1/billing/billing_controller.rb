class Api::V1::Billing::BillingController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?
  skip_before_action :validate_billing_status

  def show
    subscription = @current_account.billing_subscription
    invoices = @current_account.billing_invoices.order(created_at: :desc)

    plans = Billing::Plan.all.map do |p|
      {
        id: p.id,
        stripe_price_id: p.stripe_price_id,
        name: p.name,
        amount: p.amount.to_f,
        currency: p.currency
      }
    end

    render json: {
      subscription: subscription_payload(subscription),
      invoices: invoices_payload(invoices),
      plans: plans
    }
  end

  def checkout
    price_id = params[:price_id]
    if price_id.blank?
      render json: { error: 'O price_id do Stripe é obrigatório.' }, status: :unprocessable_entity
      return
    end

    service = Billing::StripeBillingService.new(@current_account)
    checkout_url = service.create_checkout_session(price_id)
    render json: { url: checkout_url }
  rescue StandardError => e
    render json: { error: e.message }, status: :bad_request
  end

  def portal
    service = Billing::StripeBillingService.new(@current_account)
    portal_url = service.create_portal_session
    render json: { url: portal_url }
  rescue StandardError => e
    render json: { error: e.message }, status: :bad_request
  end

  private

  def subscription_payload(subscription)
    return { status: 'none', billing_enabled: billing_enabled? } if subscription.blank?

    {
      id: subscription.id,
      stripe_subscription_id: subscription.stripe_subscription_id,
      stripe_customer_id: subscription.stripe_customer_id,
      plan_name: subscription.plan_name,
      amount: subscription.amount.to_f,
      currency: subscription.currency,
      status: subscription.status,
      current_period_end: subscription.current_period_end,
      next_payment_at: subscription.next_payment_at,
      last_payment_at: subscription.last_payment_at,
      blocked: subscription.blocked?,
      billing_enabled: billing_enabled?
    }
  end

  def invoices_payload(invoices)
    invoices.map do |inv|
      files = inv.invoice_files.map do |f|
        {
          id: f.id,
          filename: f.filename,
          url: begin
            Rails.application.routes.url_helpers.rails_blob_url(f.file, only_path: true)
          rescue StandardError
            nil
          end
        }
      end
      {
        id: inv.id,
        stripe_invoice_id: inv.stripe_invoice_id,
        amount: inv.amount.to_f,
        currency: inv.currency,
        status: inv.status,
        invoice_url: inv.invoice_url,
        invoice_pdf: inv.invoice_pdf,
        created_at: inv.created_at,
        files: files
      }
    end
  end

  def billing_enabled?
    setting = @current_account.billing_setting
    setting.nil? || setting.billing_enabled?
  end
end
