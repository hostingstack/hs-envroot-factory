# -*- mode: ruby -*-
task :default => [:test]

require 'rbconfig'
RUBY_INTERPRETER = File.join(Config::CONFIG["bindir"], Config::CONFIG["RUBY_INSTALL_NAME"] + Config::CONFIG["EXEEXT"])

desc "Run Tests"
task :test do
  require File.expand_path('../test/test_helper', __FILE__)

  Dir.glob(File.expand_path('../test', __FILE__)+ "/*_test.rb").each do |fn|
    require fn
  end
end

task :build => [:buildversion]

task :buildversion do
  version = %x{git describe --always --dirty}.chomp
  puts "Saving version stamp: #{version}"
  File.open('lib/envrootfactoryversion.rb', 'w') do |f|
    f.write "# This file is automatically generated by rake buildversion\n"
    f.write "EnvrootFactoryVersion = %s\n" % version.inspect
  end
end

BIN_FILES = ['envroot-factory', 'envroot-factory-rebuild-template']
require File.expand_path('../lib/tasks/jruby', __FILE__)
