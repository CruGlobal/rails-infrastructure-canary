require "sidekiq/pro/web"

Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Defines the root path route ("/")
  root "main#hello"

  get "main/hello"
  get "monitors/lb"

  mount Sidekiq::Web => "/sidekiq"
end
