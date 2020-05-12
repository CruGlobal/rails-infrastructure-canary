Rails.application.routes.draw do
  # For details on the DSL available within this file, see https://guides.rubyonrails.org/routing.html

  get "main/hello"
  get "monitors/lb"
  root "main#hello"
end
