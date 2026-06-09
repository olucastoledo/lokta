class Api::V1::Billing::AdminBillingController < Api::BaseController
  before_action :require_super_admin!

  def index
    accounts = Account.order(id: :desc)

    accounts = accounts.where('name ILIKE ?', "%#{params[:q]}%") if params[:q].present?

    accounts = accounts.joins(:billing_subscription).where(billing_subscriptions: { status: params[:status] }) if params[:status].present?

    page = (params[:page] || 1).to_i
    per_page = 20
    total_count = accounts.count
    accounts = accounts.offset((page - 1) * per_page).limit(per_page)

    records = accounts.map do |acc|
      sub = acc.billing_subscription
      setting = acc.billing_setting

      {
        id: acc.id,
        name: acc.name,
        created_at: acc.created_at,
        billing_enabled: setting.nil? || setting.billing_enabled?,
        subscription: if sub.present?
                        {
                          id: sub.id,
                          stripe_customer_id: sub.stripe_customer_id,
                          stripe_subscription_id: sub.stripe_subscription_id,
                          plan_name: sub.plan_name,
                          amount: sub.amount.to_f,
                          currency: sub.currency,
                          status: sub.status,
                          current_period_end: sub.current_period_end,
                          trial_end: sub.trial_end,
                          blocked_at: sub.blocked_at
                        }
                      end
      }
    end

    render json: {
      accounts: records,
      meta: {
        current_page: page,
        total_pages: (total_count.to_f / per_page).ceil,
        total_count: total_count
      }
    }
  end

  def show
    account = Account.find(params[:id])
    sub = account.billing_subscription
    setting = account.billing_setting
    invoices = account.billing_invoices.order(created_at: :desc)
    events = account.billing_events.order(created_at: :desc).limit(50)

    render json: {
      account: {
        id: account.id,
        name: account.name,
        created_at: account.created_at,
        billing_enabled: setting.nil? || setting.billing_enabled?
      },
      subscription: if sub.present?
                      {
                        id: sub.id,
                        stripe_customer_id: sub.stripe_customer_id,
                        stripe_subscription_id: sub.stripe_subscription_id,
                        stripe_price_id: sub.stripe_price_id,
                        stripe_product_id: sub.stripe_product_id,
                        plan_name: sub.plan_name,
                        amount: sub.amount.to_f,
                        currency: sub.currency,
                        status: sub.status,
                        current_period_end: sub.current_period_end,
                        trial_end: sub.trial_end,
                        blocked_at: sub.blocked_at
                      }
                    end,
      invoices: invoices.map do |inv|
        {
          id: inv.id,
          stripe_invoice_id: inv.stripe_invoice_id,
          amount: inv.amount.to_f,
          currency: inv.currency,
          status: inv.status,
          invoice_url: inv.invoice_url,
          invoice_pdf: inv.invoice_pdf,
          created_at: inv.created_at,
          files: inv.invoice_files.map do |f|
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
        }
      end,
      events: events.map do |ev|
        {
          id: ev.id,
          event_type: ev.event_type,
          description: ev.description,
          created_at: ev.created_at
        }
      end
    }
  end

  def update
    account = Account.find(params[:id])

    if params.key?(:billing_enabled)
      setting = Billing::AccountSetting.find_or_initialize_by(account_id: account.id)
      setting.update!(billing_enabled: params[:billing_enabled])
    end

    if params.key?(:subscription)
      sub_params = params[:subscription]
      sub = Billing::Subscription.find_or_initialize_by(account_id: account.id)

      # Determine if status changed
      status_changed = sub.status != sub_params[:status]

      sub.update!(
        stripe_customer_id: sub_params[:stripe_customer_id],
        stripe_subscription_id: sub_params[:stripe_subscription_id],
        stripe_price_id: sub_params[:stripe_price_id],
        stripe_product_id: sub_params[:stripe_product_id],
        plan_name: sub_params[:plan_name],
        amount: sub_params[:amount],
        currency: sub_params[:currency],
        status: sub_params[:status],
        current_period_end: sub_params[:current_period_end],
        trial_end: sub_params[:trial_end]
      )

      if sub.blocked?
        sub.update!(blocked_at: sub.blocked_at || Time.zone.now)
      else
        sub.update!(blocked_at: nil)
      end

      Billing::Event.create!(
        account_id: account.id,
        event_type: 'subscription_manual_update',
        description: "Assinatura atualizada manualmente pelo Super Admin. Novo status: #{sub.status}."
      )

      # Trigger n8n hook if subscription status changed
      trigger_n8n_subscription_changed(account, sub) if status_changed
    end

    render json: { success: true }
  end

  def sync
    account = Account.find(params[:id])
    sub = account.billing_subscription

    if sub.blank? || sub.stripe_subscription_id.blank?
      render json: { error: 'Esta conta não possui um ID de assinatura Stripe vinculado.' }, status: :unprocessable_entity
      return
    end

    service = Billing::StripeBillingService.new(account)
    success = service.sync_subscription

    if success
      render json: { success: true, message: 'Assinatura sincronizada com sucesso.' }
    else
      render json: { error: 'Falha ao sincronizar assinatura.' }, status: :bad_request
    end
  rescue StandardError => e
    render json: { error: e.message }, status: :bad_request
  end

  def upload_file
    invoice = Billing::Invoice.find(params[:id])
    file = params[:file]

    if file.blank?
      render json: { error: 'Nenhum arquivo enviado.' }, status: :unprocessable_entity
      return
    end

    invoice_file = Billing::InvoiceFile.new(
      invoice: invoice,
      filename: file.original_filename
    )
    invoice_file.file.attach(file)

    if invoice_file.save
      Billing::Event.create!(
        account_id: invoice.account_id,
        event_type: 'invoice_file_uploaded',
        description: "Nota fiscal / arquivo de fatura enviado: #{file.original_filename}."
      )

      trigger_n8n_invoice_uploaded(invoice, invoice_file)

      render json: {
        success: true,
        file: {
          id: invoice_file.id,
          filename: invoice_file.filename,
          url: begin
            Rails.application.routes.url_helpers.rails_blob_url(invoice_file.file, only_path: true)
          rescue StandardError
            nil
          end
        }
      }
    else
      render json: { error: invoice_file.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end
  end

  private

  def require_super_admin!
    render json: { error: 'Acesso não autorizado.' }, status: :unauthorized unless current_user.is_a?(SuperAdmin)
  end

  def trigger_n8n_subscription_changed(account, subscription)
    n8n_url = ENV.fetch('N8N_BILLING_WEBHOOK_URL', nil)
    return if n8n_url.blank?

    event_type = if subscription.status == 'unpaid'
                   'billing.subscription_unpaid'
                 elsif %w[blocked past_due unpaid canceled].include?(subscription.status)
                   'billing.subscription_blocked'
                 else
                   'billing.subscription_active'
                 end

    Thread.new do
      HTTParty.post(
        n8n_url,
        body: {
          event_type: event_type,
          account_id: account.id,
          account_name: account.name,
          stripe_customer_id: subscription.stripe_customer_id,
          subscription_status: subscription.status
        }.to_json,
        headers: { 'Content-Type' => 'application/json' },
        timeout: 5
      )
    rescue StandardError => e
      Rails.logger.error "[Billing n8n Webhook] Error calling n8n for sub change: #{e.message}"
    end
  end

  def trigger_n8n_invoice_uploaded(invoice, invoice_file)
    n8n_url = ENV.fetch('N8N_BILLING_WEBHOOK_URL', nil)
    return if n8n_url.blank?

    url = begin
      Rails.application.routes.url_helpers.rails_blob_url(invoice_file.file, only_path: true)
    rescue StandardError
      nil
    end
    frontend_host = ENV.fetch('FRONTEND_URL', 'localhost:3000')
    protocol = frontend_host.start_with?('http') ? '' : 'https://'
    full_url = url ? "#{protocol}#{frontend_host}#{url}" : nil

    Thread.new do
      HTTParty.post(
        n8n_url,
        body: {
          event_type: 'billing.invoice_uploaded',
          account_id: invoice.account_id,
          account_name: invoice.account&.name,
          invoice_id: invoice.id,
          stripe_invoice_id: invoice.stripe_invoice_id,
          file_id: invoice_file.id,
          filename: invoice_file.filename,
          file_url: full_url
        }.to_json,
        headers: { 'Content-Type' => 'application/json' },
        timeout: 5
      )
    rescue StandardError => e
      Rails.logger.error "[Billing n8n Webhook] Error calling n8n for invoice upload: #{e.message}"
    end
  end
end
