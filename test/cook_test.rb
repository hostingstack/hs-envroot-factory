#!/usr/bin/env ruby

require File.expand_path('../test_helper', __FILE__)

describe "Recipe Serialization/Execution" do
  setup do
    # Execute VM commands directly in host
    class FakeOpenVZ
      def initialize; @exec_output = []; end
      def exec_output; @exec_output; end
      def spawn(cmd); exec(cmd); end
      def exec(cmd)
        output = `#{cmd}`
        @exec_output << output
        output
      end
      def path_root; ""; end
    end
    ENV.delete('RUBYOPT')
    AppCode.any_instance.stubs(:files).returns ['Gemfile.lock', 'README']
    AppCode.any_instance.stubs(:read_file).returns ""
    Cook.any_instance.stubs(:log).returns nil
    FileUtils.mkdir File.expand_path('../tmp', __FILE__) rescue nil
  end

  it "should serialize the recipe to a file, and then execute it" do
    class BasicTemplate < RecipeTemplate
      @supported_types = [:basic]
      @recipe_class = Recipe::Ruby

      define_tasks :install do
        run_cmd "echo 'install'"
      end

      define_tasks :install_fast do
        run_cmd "echo 'install_fast'"
      end

      define_tasks :post_install do
        run_cmd "echo 'post install'"
      end
    end

    job_desc = EnvRootFactory::BuildRootJobDescription.new
    job_desc.job_token = "dummy"
    job_desc.app_code_url = "http://dummy/url"
    job_desc.facts = {'type' => 'basic'}
    job_desc.service_config = {}
    job_desc.prev_recipe_hash = nil

    cook = Cook.new job_desc
    @vm = FakeOpenVZ.new
    cook.instance_variable_set :@vm, @vm
    cook.instance_variable_set :@recipe_serialized_path, File.expand_path('../tmp/rr.rb', __FILE__)
    cook.generate_recipe
    cook.copy_recipe_serialized
    cook.execute_task_install
    cook.execute_task_post_install
    @vm.exec_output[0].should == "* Executing \"echo 'install'\"\n   install\n"
    @vm.exec_output[1].should == "* Executing \"echo 'post install'\"\n   post install\n"
  end
end
