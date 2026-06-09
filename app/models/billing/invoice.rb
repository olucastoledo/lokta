class Billing::Invoice < ApplicationRecord
  self.table_name = 'billing_invoices'

  belongs_to :account
  has_many :invoice_files, class_name: 'Billing::InvoiceFile', foreign_key: :billing_invoice_id, dependent: :destroy

  validates :account_id, presence: true
  validates :amount, presence: true
  validates :currency, presence: true
  validates :status, presence: true
end
