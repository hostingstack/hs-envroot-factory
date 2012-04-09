class RecipeGenerator
  class NoTemplateFoundError < StandardError; end

  def self.choose_recipe_template(facts)
    RecipeTemplate.known_subclasses.each do |kls|
      return kls if kls.try_choose facts
    end
    raise NoTemplateFoundError
  end

  def self.generate(facts = {}, app_code = nil, service_config = {}, system_facts = {}, app_logger = Logger.new(STDOUT))
    generator = self.choose_recipe_template facts

    task_lists = {}
    [:install, :install_fast, :post_install].each do |name|
      tl = TaskList.new
      tl.instance_variable_set :@app_code, app_code
      tl.instance_variable_set :@facts, facts
      tl.instance_variable_set :@service_config, service_config
      tl.instance_variable_set :@system_facts, system_facts
      tl.instance_variable_set :@app_logger, app_logger
      tl.instance_eval &generator.task_blocks[name]
      task_lists[name] = tl.out
    end

    generator.recipe_class.new(task_lists, facts, $config[:vm_app_code_path], system_facts)
  end

end
