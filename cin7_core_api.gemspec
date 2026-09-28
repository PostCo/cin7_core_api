# frozen_string_literal: true

require_relative "lib/cin7_core_api/version"

Gem::Specification.new do |spec|
  spec.name = "cin7_core_api"
  spec.version = Cin7CoreAPI::VERSION
  spec.authors = ["PostCo"]
  spec.email = ["engineering@postco.co"]

  spec.summary = "A Ruby client for the CIN7 Core API v2"
  spec.description = "A small, explicit Ruby client for CIN7 Core API v2 reads and writes, without automatic retries."
  spec.homepage = "https://github.com/PostCo/cin7_core_api"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir[
    "CHANGELOG.md",
    "LICENSE.txt",
    "README.md",
    "lib/**/*.rb"
  ]
  spec.require_paths = ["lib"]

  spec.add_dependency "faraday", ">= 2.7", "< 3"
  spec.add_dependency "uri", ">= 0.11", "< 2"

  spec.add_development_dependency "rake", ">= 13.0"
  spec.add_development_dependency "rspec", ">= 3.12", "< 4"
  spec.add_development_dependency "standard", ">= 1.35", "< 2"
end
