class Billing::InvoiceFile < ApplicationRecord
  self.table_name = 'billing_invoice_files'

  belongs_to :invoice, class_name: 'Billing::Invoice', foreign_key: :billing_invoice_id

  has_one_attached :file

  validates :billing_invoice_id, presence: true
  validates :filename, presence: true
end
