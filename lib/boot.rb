ENV['BUNDLE_GEMFILE'] = File.expand_path('../../Gemfile', __FILE__)
require 'rubygems'
require 'bundler/setup'
Bundler.require(:default)
# add ourselves to front of load path
$:.insert(0, File.expand_path('..', __FILE__))
# these are supposed to be hoster-modifiable, so they can't go into lib
$:.insert(0, File.expand_path('../../recipe-lib', __FILE__))

# TemplateArchiveBuilder, Cook assume this.
File.umask(0022)

begin
  $stdout.sync = true
rescue
end

require 'support'
require 'support_shared'
require 'app_code'
require 'openvz'
require 'build_root_job'
require 'cook'
require 'recipe_generator'
# loads recipes, too
require 'recipe_template'

begin
  require 'envrootfactoryversion'
rescue LoadError
  begin
    EnvrootFactoryVersion = %x{git describe --always --dirty}.chomp + "-dev"
  rescue Exception
  end
end
