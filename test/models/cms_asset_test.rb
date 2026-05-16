require "test_helper"
require "erb"
require "stringio"
require "yaml"

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

  test "amazon storage config keeps bucket private and omits acl settings" do
    with_modified_env(
      "AWS_ACCESS_KEY_ID" => "placeholder-access-key",
      "AWS_SECRET_ACCESS_KEY" => "placeholder-secret-key",
      "AWS_REGION" => "ap-southeast-2",
      "AWS_S3_BUCKET" => "tdk-assets-test",
      "PUBLIC_UPLOAD_ASSET_HOST" => "https://assets.example.test",
      "PUBLIC_UPLOAD_CACHE_CONTROL" => "public, max-age=60"
    ) do
      amazon = rendered_storage_config.fetch("amazon")

      assert_equal "S3", amazon.fetch("service")
      assert_equal "tdk-assets-test", amazon.fetch("bucket")
      assert_equal "public, max-age=60", amazon.fetch("upload").fetch("cache_control")
      assert_no_acl_settings amazon
      assert_not amazon.key?("public")
    end
  end

  private

  def rendered_storage_config
    YAML.safe_load(
      ERB.new(Rails.root.join("config/storage.yml").read).result,
      aliases: true
    )
  end

  def assert_no_acl_settings(value)
    case value
    when Hash
      value.each do |key, nested_value|
        assert_not_equal "acl", key.to_s
        assert_no_acl_settings nested_value
      end
    when Array
      value.each { |nested_value| assert_no_acl_settings nested_value }
    else
      assert_not_equal "public-read", value.to_s
    end
  end
end
