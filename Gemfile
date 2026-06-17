# frozen_string_literal: true

source "https://rubygems.org"

# Runtime dependencies are declared in the gemspec.
gemspec

group :development, :test do
  gem "rake", "~> 13.0"
  gem "minitest", "~> 5.0"
  gem "mocha", "~> 2.0"
  # Needed only to load sidekiq/web in the Web tab test.
  gem "rack", ">= 2.2"
end
