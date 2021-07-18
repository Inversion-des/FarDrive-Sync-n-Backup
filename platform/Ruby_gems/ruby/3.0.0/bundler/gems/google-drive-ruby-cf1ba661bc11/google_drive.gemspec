# -*- encoding: utf-8 -*-
# stub: google_drive 3.0.7 ruby lib

Gem::Specification.new do |s|
  s.name = "google_drive".freeze
  s.version = "3.0.7"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Hiroshi Ichikawa".freeze]
  s.date = "2021-07-03"
  s.description = "A library to read/write files/spreadsheets in Google Drive/Docs.".freeze
  s.email = ["gimite+github@gmail.com".freeze]
  s.files = ["README.md".freeze, "lib/google_drive".freeze, "lib/google_drive.rb".freeze, "lib/google_drive/access_token_credentials.rb".freeze, "lib/google_drive/acl.rb".freeze, "lib/google_drive/acl_entry.rb".freeze, "lib/google_drive/api_client_fetcher.rb".freeze, "lib/google_drive/authentication_error.rb".freeze, "lib/google_drive/collection.rb".freeze, "lib/google_drive/config.rb".freeze, "lib/google_drive/error.rb".freeze, "lib/google_drive/file.rb".freeze, "lib/google_drive/list.rb".freeze, "lib/google_drive/list_row.rb".freeze, "lib/google_drive/response_code_error.rb".freeze, "lib/google_drive/session.rb".freeze, "lib/google_drive/spreadsheet.rb".freeze, "lib/google_drive/util.rb".freeze, "lib/google_drive/worksheet.rb".freeze]
  s.homepage = "https://github.com/gimite/google-drive-ruby".freeze
  s.licenses = ["BSD-3-Clause".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.0.0".freeze)
  s.rubygems_version = "3.2.17".freeze
  s.summary = "A library to read/write files/spreadsheets in Google Drive/Docs.".freeze

  s.installed_by_version = "3.2.17" if s.respond_to? :installed_by_version

  if s.respond_to? :specification_version then
    s.specification_version = 4
  end

  if s.respond_to? :add_runtime_dependency then
    s.add_runtime_dependency(%q<nokogiri>.freeze, [">= 1.5.3", "< 2.0.0"])
    s.add_runtime_dependency(%q<google-apis-drive_v3>.freeze, [">= 0.5.0", "< 1.0.0"])
    s.add_runtime_dependency(%q<google-apis-sheets_v4>.freeze, [">= 0.4.0", "< 1.0.0"])
    s.add_runtime_dependency(%q<googleauth>.freeze, [">= 0.5.0", "< 1.0.0"])
    s.add_development_dependency(%q<test-unit>.freeze, [">= 3.0.0", "< 4.0.0"])
    s.add_development_dependency(%q<rake>.freeze, [">= 0.8.0"])
    s.add_development_dependency(%q<rspec-mocks>.freeze, [">= 3.4.0", "< 4.0.0"])
  else
    s.add_dependency(%q<nokogiri>.freeze, [">= 1.5.3", "< 2.0.0"])
    s.add_dependency(%q<google-apis-drive_v3>.freeze, [">= 0.5.0", "< 1.0.0"])
    s.add_dependency(%q<google-apis-sheets_v4>.freeze, [">= 0.4.0", "< 1.0.0"])
    s.add_dependency(%q<googleauth>.freeze, [">= 0.5.0", "< 1.0.0"])
    s.add_dependency(%q<test-unit>.freeze, [">= 3.0.0", "< 4.0.0"])
    s.add_dependency(%q<rake>.freeze, [">= 0.8.0"])
    s.add_dependency(%q<rspec-mocks>.freeze, [">= 3.4.0", "< 4.0.0"])
  end
end
