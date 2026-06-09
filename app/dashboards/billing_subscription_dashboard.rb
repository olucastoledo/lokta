require 'administrate/base_dashboard'

class BillingSubscriptionDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    account: Field::BelongsToSearch.with_options(
      class_name: 'Account',
      searchable: true,
      searchable_field: [:name, :id],
      order: 'id DESC'
    ),
    id: Field::Number.with_options(searchable: true),
    stripe_customer_id: Field::String.with_options(searchable: true),
    stripe_subscription_id: Field::String.with_options(searchable: true),
    stripe_price_id: Field::String,
    stripe_product_id: Field::String,
    plan_name: Field::String.with_options(searchable: true),
    amount: Field::Number.with_options(decimals: 2),
    currency: Field::String,
    status: Field::Select.with_options(collection: %w[active trialing past_due unpaid canceled blocked]),
    current_period_start: Field::DateTime,
    current_period_end: Field::DateTime,
    trial_end: Field::DateTime,
    next_payment_at: Field::DateTime,
    last_payment_at: Field::DateTime,
    blocked_at: Field::DateTime,
    cancellation_at: Field::DateTime,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    account
    plan_name
    amount
    currency
    status
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    account
    stripe_customer_id
    stripe_subscription_id
    stripe_price_id
    stripe_product_id
    plan_name
    amount
    currency
    status
    current_period_start
    current_period_end
    trial_end
    next_payment_at
    last_payment_at
    blocked_at
    cancellation_at
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[
    account
    stripe_customer_id
    stripe_subscription_id
    stripe_price_id
    stripe_product_id
    plan_name
    amount
    currency
    status
    current_period_start
    current_period_end
    trial_end
    next_payment_at
    last_payment_at
    blocked_at
    cancellation_at
  ].freeze

  def display_resource(subscription)
    "Subscription ##{subscription.id} for Account ##{subscription.account_id}"
  end
end
