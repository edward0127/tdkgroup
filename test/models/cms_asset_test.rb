require "test_helper"
require "stringio"

class CmsAssetTest < ActiveSupport::TestCase
  test "test storage is local and does not require AWS credentials" do
    with_modified_env(
      "AWS_ACCESS_KEY_ID" => nil,
      "AWS_SECRET_ACCESS_KEY" => nil,
      "AWS_REGION" => nil,
      "AWS_S3_BUCKET" => nil,
      "PUBLIC_UPLOAD_ASSET_HOST" => nil
    ) do
      assert_equal :test, Rails.application.config.active_storage.service

      asset = CmsAsset.new(key: "phase-1-test-image", alt_text_en: "Test image")
      asset.file.attach(
        io: StringIO.new("fake image data"),
        filename: "test.png",
        content_type: "image/png",
        identify: false
      )

      assert asset.valid?, asset.errors.full_messages.to_sentence
      assert asset.save
      assert asset.file.attached?
    end
  end

  test "cms seed imports authorised TDK assets" do
    seed_cms!

    logo = CmsAsset.find_by!(key: "tdk-logo")
    hero = CmsAsset.find_by!(key: "hero-handshake")

    assert logo.file.attached?
    assert hero.file.attached?
    assert_equal "TDK Group Pty Ltd logo", logo.alt_text("en")
  end

  test "cms seed repairs missing required asset attachment" do
    seed_cms!
    asset = CmsAsset.find_by!(key: "hero-handshake")
    asset.file.purge

    assert_not CmsSeeder.required_assets_attached?

    CmsSeeder.seed!
    asset.reload

    assert asset.file.attached?
    assert CmsSeeder.required_assets_attached?
  end
end
