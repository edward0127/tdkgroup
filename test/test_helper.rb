ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: 1, with: :threads)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    def seed_cms!
      CmsSeeder.seed!
    end

    def with_modified_env(values)
      previous_values = values.each_key.to_h { |key| [ key, ENV[key] ] }
      values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
      yield
    ensure
      previous_values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    end
  end
end
