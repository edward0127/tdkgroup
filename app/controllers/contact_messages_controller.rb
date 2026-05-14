class ContactMessagesController < ApplicationController
  before_action :ensure_cms_seeded

  def create
    @contact_form = ContactMessageForm.new(contact_message_params)

    if @contact_form.spam?
      redirect_to localized_slug_path("contact-us", locale: I18n.locale), notice: tdk_t("contact.thanks")
      return
    end

    if @contact_form.valid?
      ContactMailer.enquiry(@contact_form.to_payload, contact_recipient).deliver_now
      redirect_to localized_slug_path("contact-us", locale: I18n.locale), notice: tdk_t("contact.success")
    else
      render_contact_page(status: :unprocessable_entity)
    end
  rescue StandardError => e
    Rails.logger.error("Contact email delivery failed: #{e.class} - #{e.message}")
    @contact_form.errors.add(:base, tdk_t("contact.failure"))
    render_contact_page(status: :unprocessable_entity)
  end

  private

  def ensure_cms_seeded
    CmsPage.ensure_seeded!
  end

  def contact_message_params
    params.require(:contact_message_form).permit(:name, :email, :subject, :message, :website)
  end

  def contact_recipient
    ENV.fetch("CONTACT_RECIPIENT_EMAIL", "info@tdkgroup.com.au")
  end

  def render_contact_page(status:)
    @page = CmsPage.includes(:translations).find_by!(slug: "contact-us")
    @translation = @page.translation_for(I18n.locale)
    @content = @translation.content
    render "pages/show", status: status
  end
end
