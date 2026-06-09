class Billing::Plan < ApplicationRecord
  self.table_name = 'billing_plans'

  validates :stripe_product_id, presence: true
  validates :stripe_price_id, presence: true
  validates :name, presence: true
  validates :amount, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :currency, presence: true
end
