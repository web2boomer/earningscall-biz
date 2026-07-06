# frozen_string_literal: true

require_relative "lib/earningscall_biz/version"

Gem::Specification.new do |spec|
  spec.name = "earningscall-biz"
  spec.version = EarningsCallBiz::VERSION
  spec.authors = ["Alex O'Byrne"]
  spec.email = ["alex@aob.io"]

  spec.summary = "Ruby client for the EarningsCall.biz API"
  spec.description = "Ruby client for the EarningsCall.biz API"
  spec.homepage = "https://github.com/web2boomer/earningscall-biz"
  spec.required_ruby_version = ">= 2.6.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  spec.files = Dir.chdir(__dir__) do
    Dir["lib/**/*.rb", "README.md", "LICENSE.txt"]
  end
  spec.require_paths = ["lib"]

  spec.add_dependency "faraday", ">= 1.0"
end
