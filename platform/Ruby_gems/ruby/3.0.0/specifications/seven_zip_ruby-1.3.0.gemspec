# -*- encoding: utf-8 -*-
# stub: seven_zip_ruby 1.3.0 ruby lib
# stub: ext/seven_zip_ruby/extconf.rb

Gem::Specification.new do |s|
  s.name = "seven_zip_ruby".freeze
  s.version = "1.3.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Masamitsu MURASE".freeze]
  s.date = "2020-08-11"
  s.description = "SevenZipRuby (seven_zip_ruby) is a ruby gem library to read and write 7zip archives. This gem library calls official 7z.dll internally.".freeze
  s.email = ["masamitsu.murase@gmail.com".freeze]
  s.extensions = ["ext/seven_zip_ruby/extconf.rb".freeze]
  s.files = ["ext/seven_zip_ruby/extconf.rb".freeze]
  s.homepage = "https://github.com/masamitsu-murase/seven_zip_ruby".freeze
  s.licenses = ["LGPL + unRAR".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.0.0".freeze)
  s.rubygems_version = "3.2.17".freeze
  s.summary = "This is a ruby gem library to read and write 7zip files.".freeze

  s.installed_by_version = "3.2.17" if s.respond_to? :installed_by_version

  if s.respond_to? :specification_version then
    s.specification_version = 4
  end

  if s.respond_to? :add_runtime_dependency then
    s.add_development_dependency(%q<bundler>.freeze, [">= 0"])
    s.add_development_dependency(%q<rake>.freeze, [">= 0"])
    s.add_development_dependency(%q<rspec>.freeze, [">= 0"])
  else
    s.add_dependency(%q<bundler>.freeze, [">= 0"])
    s.add_dependency(%q<rake>.freeze, [">= 0"])
    s.add_dependency(%q<rspec>.freeze, [">= 0"])
  end
end
