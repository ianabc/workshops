# Copyright (c) 2019 Banff International Research Station.
# This file is part of Workshops. Workshops is licensed under
# the GNU Affero General Public License as published by the
# Free Software Foundation, version 3 of the License.
# See the COPYRIGHT file for details and exceptions.

require 'rails_helper'

RSpec.describe 'API Sign-in', type: :request do
  let(:url) { '/api/login' }

  before do
    @user = create(:user, role: :staff)
    @event = create(:event_with_members)
  end

  it 'rejects html requests' do
    params = {
      'Accept' => 'application/html',
      'Content-Type' => 'application/html',
      user: {
        email: @user.email,
        password: @user.password
      }
    }

    post '/api/login.html', params: params

    expect(response).to have_http_status(406)
    expect(response.header['Authorization']).to be_blank
  end

  context 'JSON without auth_headers' do
    it 'Given valid credentials, returns an Authorization token' do
      params = {
        'Accept' => 'application/json',
        'Content-Type' => 'application/json',
        api_user: {
          email: @user.email,
          password: @user.password
        }
      }
      post url, params: params

      expect(response.header['Authorization']).to match(/Bearer/)
    end

    it 'Authorization token can be used to access protected resources' do
      params = {
        'Accept' => 'application/json',
        'Content-Type' => 'application/json',
        api_user: {
          email: @user.email,
          password: @user.password
        }
      }
      post url, params: params

      expect(response.header['Authorization']).to match(/Bearer/)

      auth_token = response.header['Authorization']
      auth_headers = {
        'Authorization' => auth_token,
        'Accept' => 'application/json'
      }

      memberships_url = event_memberships_url(@event) + '.json'
      get memberships_url, params: {}, headers: auth_headers

      expect(response.status).to eq(200)
      member = @event.memberships.first
      expect(response.body).to include(member.staff_notes)
      expect(response.body).to include(member.person.email)
    end

    it 'does not provide access for non-staff users' do
      @user.member!
      params = {
        'Accept' => 'application/json',
        'Content-Type' => 'application/json',
        api_user: {
          email: @user.email,
          password: @user.password
        }
      }
      post url, params: params

      auth_token = response.header['Authorization']
      auth_headers = {
        'Authorization' => auth_token,
        'Accept' => 'application/json'
      }

      memberships_url = event_memberships_url(@event) + '.json'
      get memberships_url, params: {}, headers: auth_headers

      expect(response.status).to eq(302)
      member = @event.memberships.first
      expect(response.body).not_to include(member.person.email)

      @user.staff!
    end

    it 'does not provide Authorization token with invalid credentials' do
      params = {
        'Accept' => 'application/json',
        'Content-Type' => 'application/json',
        api_user: {
          email: @user.email,
          password: 'foo'
        }
      }
      post url, params: params
      expect(response.header['Authorization']).to be_blank
    end
  end
end
