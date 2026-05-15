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

  test "uploaded images are limited to supported content types" do
    asset = CmsAsset.new(key: "phase-3-invalid-type", alt_text_en: "Invalid file")
    asset.file.attach(
      io: StringIO.new("not an image"),
      filename: "file.txt",
      content_type: "text/plain",
      identify: false
    )

    assert_not asset.valid?
    assert_includes asset.errors[:file], "must be a JPEG, PNG, WebP or GIF image"
  end

  test "uploaded images are limited to eight megabytes" do
    asset = CmsAsset.new(key: "phase-3-too-large", alt_text_en: "Large image")
    asset.file.attach(
      io: StringIO.new("x" * (CmsAsset::MAX_FILE_SIZE + 1)),
      filename: "large.png",
      content_type: "image/png",
      identify: false
    )

    assert_not asset.valid?
    assert_includes asset.errors[:file], "must be smaller than 8 MB"
  end
end
