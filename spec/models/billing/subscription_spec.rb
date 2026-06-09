# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Billing::Subscription, type: :model do
  let!(:account) { create(:account) }
  let!(:subscription) { Billing::Subscription.create!(account_id: account.id, status: 'active') }

  describe 'validations' do
    it 'is invalid without an account' do
      sub = Billing::Subscription.new(status: 'active')
      expect(sub.valid?).to be(false)
    end

    it 'is invalid without a status' do
      sub = Billing::Subscription.new(account_id: account.id)
      expect(sub.valid?).to be(false)
    end
  end

  describe '#blocked?' do
    it 'returns false for active status' do
      subscription.update!(status: 'active')
      expect(subscription.blocked?).to be(false)
    end

    it 'returns false for trialing status' do
      subscription.update!(status: 'trialing')
      expect(subscription.blocked?).to be(false)
    end

    it 'returns true for past_due status' do
      subscription.update!(status: 'past_due')
      expect(subscription.blocked?).to be(true)
    end

    it 'returns true for unpaid status' do
      subscription.update!(status: 'unpaid')
      expect(subscription.blocked?).to be(true)
    end

    it 'returns true for canceled status' do
      subscription.update!(status: 'canceled')
      expect(subscription.blocked?).to be(true)
    end

    it 'returns true for blocked status' do
      subscription.update!(status: 'blocked')
      expect(subscription.blocked?).to be(true)
    end
  end

  describe '#active?' do
    it 'returns true for active status' do
      subscription.update!(status: 'active')
      expect(subscription.active?).to be(true)
    end

    it 'returns true for trialing status' do
      subscription.update!(status: 'trialing')
      expect(subscription.active?).to be(true)
    end

    it 'returns false for unpaid status' do
      subscription.update!(status: 'unpaid')
      expect(subscription.active?).to be(false)
    end
  end
end
