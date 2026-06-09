class CreateBillingTables < ActiveRecord::Migration[7.1]
  def change
    create_table :billing_plans do |t|
      t.string :stripe_product_id
      t.string :stripe_price_id
      t.string :name
      t.decimal :amount, precision: 10, scale: 2
      t.string :currency

      t.timestamps
    end
    add_index :billing_plans, :stripe_product_id
    add_index :billing_plans, :stripe_price_id

    create_table :billing_subscriptions do |t|
      t.bigint :account_id, null: false
      t.string :stripe_customer_id
      t.string :stripe_subscription_id
      t.string :stripe_price_id
      t.string :stripe_product_id
      t.string :plan_name
      t.decimal :amount, precision: 10, scale: 2
      t.string :currency
      t.string :status
      t.datetime :current_period_start
      t.datetime :current_period_end
      t.datetime :trial_end
      t.datetime :next_payment_at
      t.datetime :last_payment_at
      t.datetime :blocked_at
      t.datetime :cancellation_at
      t.jsonb :metadata, default: {}

      t.timestamps
    end
    add_index :billing_subscriptions, :account_id, unique: true
    add_index :billing_subscriptions, :stripe_customer_id
    add_index :billing_subscriptions, :stripe_subscription_id
    add_index :billing_subscriptions, :status

    create_table :billing_invoices do |t|
      t.bigint :account_id, null: false
      t.string :stripe_invoice_id
      t.string :stripe_customer_id
      t.string :stripe_subscription_id
      t.decimal :amount, precision: 10, scale: 2
      t.string :currency
      t.string :status
      t.string :invoice_url
      t.string :invoice_pdf

      t.timestamps
    end
    add_index :billing_invoices, :account_id
    add_index :billing_invoices, :stripe_invoice_id

    create_table :billing_invoice_files do |t|
      t.bigint :billing_invoice_id, null: false
      t.string :filename

      t.timestamps
    end
    add_index :billing_invoice_files, :billing_invoice_id

    create_table :billing_events do |t|
      t.bigint :account_id, null: false
      t.string :event_type
      t.text :description
      t.jsonb :metadata, default: {}

      t.timestamps
    end
    add_index :billing_events, :account_id

    create_table :account_billing_settings do |t|
      t.bigint :account_id, null: false
      t.boolean :billing_enabled, default: true, null: false

      t.timestamps
    end
    add_index :account_billing_settings, :account_id, unique: true

    add_foreign_key :billing_subscriptions, :accounts, on_delete: :cascade
    add_foreign_key :billing_invoices, :accounts, on_delete: :cascade
    add_foreign_key :billing_invoice_files, :billing_invoices, on_delete: :cascade
    add_foreign_key :billing_events, :accounts, on_delete: :cascade
    add_foreign_key :account_billing_settings, :accounts, on_delete: :cascade
  end
end
