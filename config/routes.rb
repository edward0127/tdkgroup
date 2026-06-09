Rails.application.routes.draw do
  root "pages#show", defaults: { slug: "home" }

  post "language", to: "language_preferences#create", as: :language_preference
  get "sitemap.xml", to: "sitemaps#show", defaults: { format: :xml }

  get "home", to: redirect("/")
  get "zh", to: "pages#show", defaults: { locale: "zh", slug: "home" }, as: :zh_root
  get "zh/home-2", to: redirect("/zh")

  get "about-us", to: "pages#show", defaults: { slug: "about-us" }
  get "our-services", to: "pages#show", defaults: { slug: "our-services" }
  get "our-services/tax-services", to: "pages#show", defaults: { slug: "our-services/tax-services" }
  get "our-services/business-services", to: "pages#show", defaults: { slug: "our-services/business-services" }
  get "our-services/management-consulting", to: "pages#show", defaults: { slug: "our-services/management-consulting" }
  get "our-services/immigration-related-accounting-services", to: "pages#show", defaults: { slug: "our-services/immigration-related-accounting-services" }
  get "audit-services", to: "pages#show", defaults: { slug: "audit-services" }
  get "our-team", to: "pages#show", defaults: { slug: "our-team" }
  get "careers", to: "pages#show", defaults: { slug: "careers" }
  get "contact-us", to: "pages#show", defaults: { slug: "contact-us" }
  post "contact-us", to: "contact_messages#create"

  get "zh/about-us", to: "pages#show", defaults: { locale: "zh", slug: "about-us" }
  get "zh/our-services", to: "pages#show", defaults: { locale: "zh", slug: "our-services" }
  get "zh/our-services/tax-services", to: "pages#show", defaults: { locale: "zh", slug: "our-services/tax-services" }
  get "zh/our-services/business-services", to: "pages#show", defaults: { locale: "zh", slug: "our-services/business-services" }
  get "zh/our-services/management-consulting", to: "pages#show", defaults: { locale: "zh", slug: "our-services/management-consulting" }
  get "zh/our-services/immigration-related-accounting-services", to: "pages#show", defaults: { locale: "zh", slug: "our-services/immigration-related-accounting-services" }
  get "zh/audit-services", to: "pages#show", defaults: { locale: "zh", slug: "audit-services" }
  get "zh/our-team", to: "pages#show", defaults: { locale: "zh", slug: "our-team" }
  get "zh/careers", to: "pages#show", defaults: { locale: "zh", slug: "careers" }
  get "zh/contact-us", to: "pages#show", defaults: { locale: "zh", slug: "contact-us" }
  post "zh/contact-us", to: "contact_messages#create", defaults: { locale: "zh" }

  get "zh/公司简介", to: redirect("/zh/about-us")
  get "zh/联系我们-2", to: redirect("/zh/contact-us")
  get "zh/我们的服务", to: redirect("/zh/our-services")
  get "zh/我们的服务/税务服务", to: redirect("/zh/our-services/tax-services")
  get "zh/我们的服务/商业会计服务", to: redirect("/zh/our-services/business-services")
  get "zh/我们的服务/管理咨询与财务服务", to: redirect("/zh/our-services/management-consulting")
  get "zh/我们的服务/移民相关会计服务", to: redirect("/zh/our-services/immigration-related-accounting-services")
  get "zh/职业机会", to: redirect("/zh/careers")
  get "zh/我们的团队", to: redirect("/zh/our-team")

  get "services-2/audit-service", to: redirect("/audit-services")
  get "services-2/immigration-related-accounting-service", to: redirect("/our-services/immigration-related-accounting-services")
  get "zh/services-2/audit-service", to: redirect("/zh/audit-services")
  get "immigration-related-accounting-services", to: redirect("/our-services/immigration-related-accounting-services")
  get "our-services/management-consulting-and-financial-services", to: redirect("/our-services/management-consulting")
  get "author/tdkgroup", to: redirect("/")
  get "zh/author/tdkgroup", to: redirect("/zh")

  namespace :admin do
    root "dashboard#show"
    get "login", to: "sessions#new", as: :login
    post "login", to: "sessions#create"
    delete "logout", to: "sessions#destroy", as: :logout

    namespace :bas do
      root "dashboard#show"

      resources :clients
      resources :jobs do
        resource :matching, only: [ :show ], controller: "matching" do
          post :run
          post :generate_queries
        end
        resources :matches, only: [ :index, :show, :new, :create ] do
          member do
            post :accept
            post :reject
            post :mark_needs_review
          end
        end
        resources :import_runs, only: [ :index, :new, :create, :show ] do
          member do
            post :confirm
            post :revert
          end
        end
        resources :bank_transactions, only: [ :index, :show ] do
          member do
            post :ignore
            post :mark_needs_review
            post :restore
          end
        end
        resources :invoices, only: [ :index, :show ] do
          member do
            post :ignore
            post :mark_needs_review
            post :restore
          end
        end
        resources :cash_transactions, only: [ :index, :show ] do
          member do
            post :ignore
            post :mark_needs_review
            post :restore
          end
        end
        resources :payroll_summaries, only: [ :index ]
        resources :adjustments, except: [ :show ]
        resources :report_snapshots, only: [ :index, :show, :create ] do
          member do
            patch :approve
            patch :lock
            get "breakdown/:label", action: :breakdown, as: :breakdown
            get :download_summary_csv
            get :download_gst_detail_csv
            get :download_breakdown_csv
            get :download_matches_csv
            get :download_queries_csv
            get :download_adjustments_csv
            get :print
          end
        end
        resource :report, only: [ :show ], controller: "reports" do
          post :calculate
        end
        resources :ai_runs, only: [ :index, :show, :create ]
        resources :ai_suggestions, only: [ :index, :show ] do
          member do
            post :accept
            post :reject
            post :mark_needs_review
          end
        end
        resources :documents do
          get :download, on: :member
        end
        resources :document_conversion_runs, only: [ :index, :show, :create ] do
          member do
            post :confirm_import
            post :confirm_import_and_match
            get :download_csv
            post :abandon
          end
        end
        resources :queries, except: [ :destroy ]
        resource :query_email_draft, only: [ :show ], controller: "query_email_drafts" do
          post :mark_waiting_for_client
        end
      end
    end

    resources :cms_pages, only: [ :index, :edit, :update ] do
      get :inline_edit, on: :member
      patch :inline_update, on: :member
      get :preview, on: :member
      post :publish, on: :member
    end
    resources :cms_assets, only: [ :index, :create, :edit, :update, :destroy ] do
      post "versions/:version_id/restore", to: "cms_assets#restore", as: :restore_version, on: :member
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check

  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
end
