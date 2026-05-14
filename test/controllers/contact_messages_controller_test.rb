require "test_helper"

class ContactMessagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    seed_cms!
    ActionMailer::Base.deliveries.clear
  end

  teardown do
    ActionMailer::Base.deliveries.clear
  end

  test "invalid contact form re-renders contact page without sending email" do
    assert_no_difference "ActionMailer::Base.deliveries.size" do
      post "/contact-us", params: {
        contact_message_form: {
          name: "",
          email: "not-an-email",
          subject: "",
          message: "",
          website: ""
        }
      }
    end

    assert_response :unprocessable_entity
    assert_select ".form-errors"
  end

  test "valid contact form sends enquiry email" do
    with_modified_env("CONTACT_RECIPIENT_EMAIL" => "advisor@example.com") do
      assert_difference "ActionMailer::Base.deliveries.size", 1 do
        post "/contact-us", params: {
          contact_message_form: {
            name: "Client Name",
            email: "client@example.com",
            subject: "Tax planning",
            message: "Please contact me about tax planning.",
            website: ""
          }
        }
      end
    end

    assert_redirected_to "/contact-us"
    email = ActionMailer::Base.deliveries.last
    assert_equal [ "advisor@example.com" ], email.to
    assert_equal [ "client@example.com" ], email.reply_to
    assert_equal "TDK website enquiry - Tax planning", email.subject
  end

  test "honeypot submission is accepted silently without sending email" do
    assert_no_difference "ActionMailer::Base.deliveries.size" do
      post "/contact-us", params: {
        contact_message_form: {
          name: "Bot",
          email: "bot@example.com",
          subject: "Spam",
          message: "Spam",
          website: "https://example.com"
        }
      }
    end

    assert_redirected_to "/contact-us"
  end
end
