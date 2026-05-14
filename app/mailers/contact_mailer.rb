class ContactMailer < ApplicationMailer
  def enquiry(payload, recipient)
    @payload = payload.with_indifferent_access

    mail(
      to: recipient,
      reply_to: @payload[:email],
      subject: "TDK website enquiry - #{@payload[:subject]}"
    )
  end
end
