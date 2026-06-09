class Api::V1::Accounts::BaseController < Api::BaseController
  include SwitchLocale
  include EnsureCurrentAccountHelper
  before_action :current_account
  before_action :validate_billing_status
  around_action :switch_locale_using_account_locale

  private

  def validate_billing_status
    return unless @current_account&.billing_blocked?

    render json: {
      error: 'Billing Blocked',
      message: 'Sua conta está bloqueada por inadimplência. Acesse a página de faturamento para regularizar.'
    }, status: :payment_required
  end
end
