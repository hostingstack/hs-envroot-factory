class RecipeTemplate
  track_subclasses

  class << self
    attr_reader :supported_types, :recipe_class, :templates
  end
  @supported_types = []
  @recipe_class = nil

  def self.try_choose(facts)
    @supported_types.include?(facts['type'].try(:to_sym))
  end

  class << self
    def define_tasks(name, &block)
      @task_blocks ||= {}
      @task_blocks[name] = block
    end
  end
  
  def self.task_blocks
    @task_blocks
  end
end

require 'recipe'

# load recipes first, because templates will need them
(Dir.glob(File.dirname(__FILE__)+'/../recipe-lib/recipe/*.rb') - [__FILE__]).sort.each do |f|
  require f
end
(Dir.glob(File.dirname(__FILE__)+'/../recipe-lib/recipe_template/*.rb') - [__FILE__]).sort.each do |f|
  next if File.basename(f) == 'base.rb'
  require f
end
