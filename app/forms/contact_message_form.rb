class ContactMessageForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :name, :string
  attribute :email, :string
  attribute :subject, :string
  attribute :message, :string
  attribute :website, :string

  validates :name, :email, :subject, :message, presence: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :message, length: { maximum: 4000 }

  def spam?
    website.present?
  end

  def to_payload
    {
      name: name,
      email: email,
      subject: subject,
      message: message
    }
  end
end
