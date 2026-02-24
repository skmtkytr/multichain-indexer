# frozen_string_literal: true

Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      resources :blocks, only: %i[index show], param: :number
      resources :transactions, only: %i[index show], param: :hash
      resources :logs, only: [:index]
      resources :contracts, only: %i[index show], param: :address
      resources :asset_transfers, only: %i[index show]
      resources :token_contracts, only: %i[index show]

      # Address monitoring
      get 'address_transfers', to: 'address_transfers#index'

      # Webhook subscriptions
      resources :subscriptions, only: %i[index show create update destroy] do
        post :test, on: :member
        get :deliveries, on: :member
      end

      # Webhook dispatcher control
      post 'webhooks/dispatcher/start', to: 'indexer#start_dispatcher'
      post 'webhooks/dispatcher/stop', to: 'indexer#stop_dispatcher'
      get  'webhooks/dispatcher/status', to: 'indexer#dispatcher_status'

      # Chain management
      resources :chains, only: %i[index show create update destroy], param: :chain_id do
        post :test, on: :member
      end

      # Indexer control
      post 'indexer/start', to: 'indexer#start'
      post 'indexer/stop', to: 'indexer#stop'
      get  'indexer/status', to: 'indexer#status'
    end
  end

  # Direct API access (without /api/v1 namespace)
  resources :asset_transfers, only: %i[index show]
  resources :token_contracts, only: %i[index show]

  # Dashboard
  root 'dashboard#index'

  get 'health', to: proc { [200, {}, ['ok']] }
end
