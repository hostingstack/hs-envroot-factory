require 'bundler/lockfile_parser'
require 'erubis'

class RecipeTemplate::Redmine < RecipeTemplate
  @supported_types = [:redmine]
  @recipe_class = Recipe::Ruby

  define_tasks :install do
    @facts['runtime'] = 'ruby18'

    install_ruby
    install_ruby_dev

    install_gem "rake"
    install_deb "libpq-dev"

    if not @app_code.files.include?("config/environment.rb") then
      raise "config/environment.rb not found"
    end

    envrb = @app_code.read_file("config/environment.rb")
    if not @app_code.files.include?("vendor/rails") then
      # rails itself comes from gems, so we must install it, too.
      install_gem "rails", :version => envrb.split("\n").grep(/^RAILS_GEM_VERSION =/)[0].split(/ /)[2].gsub("'","")
    end

    # Need a configured db for rake gems:install...
    install_deb "libsqlite3-dev"
    install_gem "sqlite3"
    cfg = {'development' => { 'adapter' => 'sqlite3', 'database' => 'db/build.sqlite3', 'pool' => '5', 'timeout' => '1000' }}
    cfg['production'] = cfg['development']
    file_content $config[:vm_app_code_path]+'/config/database.yml', YAML.dump(cfg)

    # Now all the Gems the user wants.
    rails2_install_gems envrb.split("\n").grep(/^\s+config.gem/)
    install_injected_gems

    install_gem "unicorn"
    install_gem "pg"

    write_glue({:unicorn_bin => 'unicorn_rails',
                 :vm_app_code_path => $config[:vm_app_code_path],
                 :vm_app_home => $config[:vm_app_home],
                 :setuptask => 'rake db:migrate', :firststarttask => 'rake db:setup'})

  end

  define_tasks :install_fast do
  end

  define_tasks :post_install do
    file_content $config[:vm_app_home]+"/services.yaml", YAML.dump(@service_config)

    # create config_vars file, this stuff goes into ENV
    file_content $config[:vm_app_home]+"/config_vars", RecipeTemplate::Ruby.build_config_vars(@service_config)

    # preconfigure services for rails apps
    if @app_code.files.include?("config/environment.rb")
      # postgresql, write database.yml
      if @service_config['Postgresql']
        write_database_yml_pg $config[:vm_app_code_path]+"/config/database.yml", @service_config['Postgresql']
      end
      # memcached, write memcached.yml (only a pseudo-standard)
      if @service_config['Memcached']
        cfg = {'production' => {
            'servers' => [@service_config['Memcached']['hostname'], @service_config['Memcached']['port']]
          }
        }
        file_content $config[:vm_app_code_path]+"/config/memcached.yml", YAML.dump(cfg)
      end
    end
  end

end
