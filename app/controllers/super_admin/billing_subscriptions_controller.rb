class SuperAdmin::BillingSubscriptionsController < SuperAdmin::ApplicationController
  def resource_class
    Billing::Subscription
  end
end
