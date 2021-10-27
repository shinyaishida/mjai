# frozen_string_literal: true

Rails.application.routes.draw do
  root 'users#new'
  get '/join', to: 'users#new'
  post '/join', to: 'users#create'
  delete '/leave', to: 'users#destroy'
  get '/room', to: 'static_pages#room'
  # For details on the DSL available within this file, see https://guides.rubyonrails.org/routing.html
end
