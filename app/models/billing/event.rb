class Billing::Event < ApplicationRecord
  self.table_name = 'billing_events'

  belongs_to :account

  validates :account_id, presence: true
  validates :event_type, presence: true
  validates :description, presence: true
end
