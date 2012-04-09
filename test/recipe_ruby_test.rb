#!/usr/bin/env ruby

require File.expand_path('../test_helper', __FILE__)

describe "Recipe::Ruby" do
  setup do
  end

  it "should write a database.yml with config strings applied" do
    data = {}
    data['port'] = 4444
    data['hostname'] = "IP.ADD.RES.S"
    data['username'] = "USERNAME"
    data['password'] = "PASSWORD"
    data['database'] = "DATABASE"

    Recipe::Ruby.any_instance.expects(:file_content).with("/FOO",
                                                          all_of(regexp_matches(/production:/),
                                                                 regexp_matches(/USERNAME/),
                                                                 regexp_matches(/PASSWORD/),
                                                                 regexp_matches(/4444/),
                                                                 regexp_matches(/IP.ADD.RES.S/),
                                                                 ))
    recipe = Recipe::Ruby.new
    recipe.write_database_yml_pg("/FOO", data)
  end

  it "should be able to inject gems into a Gemfile" do
    File.expects(:exists?).returns(true)
    Recipe::Ruby.any_instance.expects(:facts).returns({'app_code' => "/TESTVIRTUAL/APPCODE"})
    File.expects(:read).with("/TESTVIRTUAL/APPCODE/Gemfile").returns("gem 'bar'\n#gem 'foo'\n")
    File.expects(:open).with("/TESTVIRTUAL/APPCODE/Gemfile", "a")
    recipe = Recipe::Ruby.new
    recipe.inject_gem "foo"
  end

  it "should not inject an existing gem into a Gemfile" do
    File.expects(:exists?).returns(true)
    Recipe::Ruby.any_instance.expects(:facts).returns({'app_code' => "/TESTVIRTUAL/APPCODE"})
    File.expects(:read).with("/TESTVIRTUAL/APPCODE/Gemfile").returns("gem 'foo'\n\n")
    recipe = Recipe::Ruby.new
    recipe.inject_gem "foo"
  end

  it "should not inject an existing gem into a Gemfile" do
    File.expects(:exists?).returns(true)
    Recipe::Ruby.any_instance.expects(:facts).returns({'app_code' => "/TESTVIRTUAL/APPCODE"})
    File.expects(:read).with("/TESTVIRTUAL/APPCODE/Gemfile").returns("gem \"foo\", '~> 2.3.0', :require 'foo'\n")
    recipe = Recipe::Ruby.new
    recipe.inject_gem "foo"
  end

  it "should mark gems to be installed later without bundler" do
    File.expects(:exists?).returns(false)
    Recipe::Ruby.any_instance.expects(:facts).returns({'app_code' => "/TESTVIRTUAL/APPCODE"})
    # XXX need test that "foo" gets saved in @injected_gems
    recipe = Recipe::Ruby.new
    recipe.inject_gem "foo"
  end
end
