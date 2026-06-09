# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Billing API and Access Guard', type: :request do
  let!(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:agent) { create(:user, account: account, role: :agent) }

  let(:admin_headers) { admin.create_new_auth_token }
  let(:agent_headers) { agent.create_new_auth_token }

  context 'when account has no subscription (active trial fallback)' do
    it 'allows accessing operational API endpoints' do
      get "/api/v1/accounts/#{account.id}/agents", headers: admin_headers, as: :json
      expect(response).to have_http_status(:success)
    end
  end

  context 'when account has active/trialing subscription' do
    before do
      Billing::Subscription.create!(account_id: account.id, status: 'active')
    end

    it 'allows accessing operational API endpoints' do
      get "/api/v1/accounts/#{account.id}/agents", headers: admin_headers, as: :json
      expect(response).to have_http_status(:success)
    end
  end

  context 'when account has blocked/past_due/unpaid subscription' do
    before do
      Billing::Subscription.create!(account_id: account.id, status: 'past_due')
    end

    it 'blocks accessing operational API endpoints with 402 Payment Required' do
      get "/api/v1/accounts/#{account.id}/agents", headers: admin_headers, as: :json
      expect(response).to have_http_status(:payment_required)
      expect(JSON.parse(response.body)['error']).to eq('Billing Blocked')
    end

    it 'allows accessing billing settings endpoint even when blocked' do
      get "/api/v1/accounts/#{account.id}/billing", headers: admin_headers, as: :json
      puts "500 Error Response Body: #{response.body}" if response.status == 500
      expect(response).to have_http_status(:success)
    end
  end
end
