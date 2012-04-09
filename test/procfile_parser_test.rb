#!/usr/bin/env ruby

require File.expand_path('../test_helper', __FILE__)
require 'procfile_parser'

describe "ProcfileParser" do
  it "should parse empty procfiles" do
    e = ProcfileParser.parse! ""
    e.should == {}
  end

  it "should parse valid procfiles" do
    e = ProcfileParser.parse! "web: echo true\nworker: echo \"true\""
    e.should == {'web' => 'echo true', 'worker' => 'echo "true"'}
  end

  it "should ignore procs without command" do
    e = ProcfileParser.parse! "web echo true\nworker: echo \"true\""
    e.should == {'worker' => 'echo "true"'}
  end

  it "should ignore comments" do
    e = ProcfileParser.parse! "#web: echo true\nworker: echo \"true\""
    e.should == {'worker' => 'echo "true"'}
  end
end
