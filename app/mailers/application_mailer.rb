class ApplicationMailer < ActionMailer::Base
  default from: -> { ENV.fetch("MAIL_FROM_EMAIL", "info@tdkgroup.com.au") }
  layout "mailer"
end
