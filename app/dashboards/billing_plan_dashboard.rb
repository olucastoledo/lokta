require 'administrate/base_dashboard'

class BillingPlanDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number.with_options(searchable: true),
    stripe_product_id: Field::String.with_options(searchable: true),
    stripe_price_id: Field::String.with_options(searchable: true),
    name: Field::String.with_options(searchable: true),
    amount: Field::Number.with_options(decimals: 2),
    currency: Field::String,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    name
    amount
    currency
    stripe_product_id
    stripe_price_id
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    name
    amount
    currency
    stripe_product_id
    stripe_price_id
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[
    name
    amount
    currency
    stripe_product_id
    stripe_price_id
  ].freeze

  def display_resource(plan)
    "Plan: #{plan.name} (#{plan.amount} #{plan.currency})"
  end
end
