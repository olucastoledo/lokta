class Billing::Subscription < ApplicationRecord
  self.table_name = 'billing_subscriptions'

  belongs_to :account

  validates :account_id, presence: true, uniqueness: true
  validates :status, presence: true

  # active, trialing, past_due, unpaid, canceled, blocked
  def blocked?
    %w[blocked unpaid past_due canceled].include?(status)
  end

  def active?
    %w[active trialing].include?(status)
  end
end
