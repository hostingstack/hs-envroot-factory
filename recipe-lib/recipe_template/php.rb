require 'bundler/lockfile_parser'
require 'erubis'

class RecipeTemplate::Php < RecipeTemplate
  @supported_types = [:php53]
  @templates = [:php53]
  @recipe_class = Recipe::Php

  def self.build_config_vars(service_config)
    config_vars = {:CLOUD => 'hs', :HS_RECIPE => 'php'}
    if service_config['Postgresql']
      db = service_config['Postgresql']
      config_vars[:DATABASE_PG_URL] = "postgres://%s:%s@%s:%d/%s" % [db['username'],db['password'],db['hostname'],db['port'],db['database']]
      # DATABASE_URL should be compatible to Heroku
      config_vars[:DATABASE_URL] = config_vars[:DATABASE_PG_URL]
    end
    if service_config['Mysql']
      db = service_config['Mysql']
      config_vars[:DATABASE_MYSQL_URL] = "mysql://%s:%s@%s:%d/%s" % [db['username'],db['password'],db['hostname'],db['port'],db['database']]
    end
    if service_config['Memcached']
      config_vars[:MEMCACHE_SERVERS] = '%s:%d' % [service_config['Memcached']['hostname'], service_config['Memcached']['port']]
    end
    config_vars.map{|k,v| 'export %s="%s"' % [k.to_s,v]}.join("\n")
  end

  define_tasks :template_build_php53 do
    @facts['runtime'] = 'php53'

    install_php
  end

  define_tasks :install do
    @facts['runtime'] = 'php53'
    @facts['app_code'] = $config[:vm_app_code_path]
    discovered_doc_root = '/'
    if @app_code.files.include?("public/index.php") || @app_code.files.include?("public/index.html")
      discovered_doc_root = '/public'
    elsif @app_code.files.include?("APP-META.xml")
      discovered_doc_root = '/htdocs'
    end
    @facts['doc_root'] ||= File.join($config[:vm_app_code_path], discovered_doc_root)

    write_glue({ :vm_app_code_path => $config[:vm_app_code_path], :vm_app_home => $config[:vm_app_home], :doc_root => @facts['doc_root'] })
  end

  define_tasks :install_fast do
  end

  define_tasks :post_install do
    file_content $config[:vm_app_home]+"/services.yaml", YAML.dump(@service_config)

    # create config_vars file, this stuff goes into ENV
    file_content $config[:vm_app_home]+"/config_vars", RecipeTemplate::Php.build_config_vars(@service_config)
  end

end
