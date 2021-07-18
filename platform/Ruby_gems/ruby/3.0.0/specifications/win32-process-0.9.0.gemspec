# -*- encoding: utf-8 -*-
# stub: win32-process 0.9.0 ruby lib

Gem::Specification.new do |s|
  s.name = "win32-process".freeze
  s.version = "0.9.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Daniel Berger".freeze, "Park Heesob".freeze]
  s.date = "2020-10-29"
  s.description = "    The win32-process library implements several Process methods that are\n    either unimplemented or dysfunctional in some way in the default Ruby\n    implementation. Examples include Process.kill, Process.uid and\n    Process.create.\n".freeze
  s.email = "djberg96@gmail.com".freeze
  s.extra_rdoc_files = ["README.md".freeze]
  s.files = ["README.md".freeze]
  s.homepage = "https://github.com/chef/win32-process".freeze
  s.licenses = ["Artistic-2.0".freeze]
  s.required_ruby_version = Gem::Requirement.new("> 1.9.0".freeze)
  s.rubygems_version = "3.2.17".freeze
  s.summary = "Adds and redefines several Process methods for Microsoft Windows".freeze

  s.installed_by_version = "3.2.17" if s.respond_to? :installed_by_version

  if s.respond_to? :specification_version then
    s.specification_version = 4
  end

  if s.respond_to? :add_runtime_dependency then
    s.add_runtime_dependency(%q<ffi>.freeze, [">= 1.0.0"])
  else
    s.add_dependency(%q<ffi>.freeze, [">= 1.0.0"])
  end
end
