#!/usr/bin/env ruby

require File.expand_path('../test_helper', __FILE__)

describe "Recipe" do
  setup do
  end

  it "should install a single deb only once" do
    Recipe.any_instance.expects(:run_cmd).once.returns(true)
    recipe = Recipe.new nil, nil, nil, nil
    recipe.install_deb ['foo', 'bar']
    recipe.install_deb ['bar']
    recipe.install_deb 'bar'
    recipe.install_deb 'foo'
    recipe.install_deb ['foo', 'bar']
    recipe.install_deb ['bar', 'foo']
  end
end
