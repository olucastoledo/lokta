class SuperAdmin::BillingPlansController < SuperAdmin::ApplicationController
  def resource_class
    Billing::Plan
  end
end
