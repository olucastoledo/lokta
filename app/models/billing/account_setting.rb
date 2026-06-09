class Billing::AccountSetting < ApplicationRecord
  self.table_name = 'account_billing_settings'

  belongs_to :account

  validates :account_id, presence: true, uniqueness: true
end
