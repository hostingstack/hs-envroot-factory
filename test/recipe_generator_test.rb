#!/usr/bin/env ruby

require File.expand_path('../test_helper', __FILE__)

describe "Recipe Generator" do
  setup do
    AppCode.any_instance.stubs(:files).returns ['Gemfile.lock', 'README']
    AppCode.any_instance.stubs(:read_file).returns ""
  end

  it "should let us define a basic task list and extract the tasks" do
    class BasicRecipe < Recipe
    end
    class BasicTemplate < RecipeTemplate
      @supported_types = [:basic]
      @recipe_class = BasicRecipe

      define_tasks :install do
        install_deb "ruby1.8-dev"
      end

      define_tasks :install_fast do
        install_deb "rubygems"
      end

      define_tasks :post_install do
        write_config "database.yml", "database.yml.template", {:local => 123}
      end
    end
    
    @app_code = AppCode.new "mocked"
    recipe = RecipeGenerator.generate({'type' => :basic}, @app_code)

    recipe.tasks[:install].should == [[:install_deb, "ruby1.8-dev"]]
    recipe.tasks[:install_fast].should == [[:install_deb, "rubygems"]]
    recipe.tasks[:post_install].should == [[:write_config, "database.yml", "database.yml.template", {:local=>123}]]
  end

  it "should raise error when type is missing in generator input" do
    class BasicTemplate < RecipeTemplate
      @supported_types = [:ruby]
    end
    should.raise(RecipeGenerator::NoTemplateFoundError) do
      RecipeGenerator.generate
    end
  end

  it "should return a recipe of the correct type" do
    class BasicRecipe < Recipe
    end
    class BasicTemplate < RecipeTemplate
      @supported_types = [:basic]
      @recipe_class = BasicRecipe
    end

    recipe = RecipeGenerator.generate({'type' => :basic}, @app_code)
    recipe.class.should == BasicRecipe
  end

  it "should support all known app types" do
    @app_code = AppCode.new "mocked"
    recipe = RecipeGenerator.generate({'type' => :rubyee18}, @app_code)
    recipe = RecipeGenerator.generate({'type' => :ruby19}, @app_code)
    recipe = RecipeGenerator.generate({'type' => :railsr19}, @app_code)
    recipe = RecipeGenerator.generate({'type' => :railsree18}, @app_code)
    # no redmine for now
    #recipe = RecipeGenerator.generate({'type' => :redmine}, @app_code)
  end

  it "should save facts determined by the template" do
    class BasicRecipe < Recipe
    end
    class BasicTemplate < RecipeTemplate
      @supported_types = [:basic]
      @recipe_class = BasicRecipe
      define_tasks :install do
        install_deb "ruby1.8-dev"
        @facts['test_install'] = 'hellothere'
      end
      define_tasks :post_install do
        @facts['test_post_install'] = 'noonehere'
      end
    end

    @app_code = AppCode.new "mocked"
    facts = {'type' => :basic}
    recipe = RecipeGenerator.generate(facts, @app_code)

    facts['test_install'].should == 'hellothere'
    facts['test_post_install'].should == 'noonehere'
  end
end
