require 'bundler/lockfile_parser'
require 'erubis'
require 'digest/sha1'

class RecipeTemplate::Ruby < RecipeTemplate
  @supported_types = [:ruby18, :ruby18, :ruby19, :railsree18, :railsr19]
  @templates = [:ruby18, :ruby19]
  @recipe_class = Recipe::Ruby

  def self.build_config_vars(service_config)
    config_vars = {:CLOUD => 'hs', :HS_RECIPE => 'ruby', :RACK_ENV => 'production', :RAILS_ENV => 'production'}
    if service_config['Postgresql']
      pg = service_config['Postgresql']
      config_vars[:DATABASE_PG_URL] = "postgres://%s:%s@%s:%d/%s" % [pg['username'],pg['password'],pg['hostname'],pg['port'],pg['database']]
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
  
  def self.override_bundler(gemfile, gemspecs, &block)
    old_gemfile_setting = ENV['BUNDLE_GEMFILE']
    old_gemspecs = Gem::Specification.all
    ENV['BUNDLE_GEMFILE'] = gemfile
    Gem::Specification.all = gemspecs
    ret = yield
    Gem::Specification.all = old_gemspecs
    ENV['BUNDLE_GEMFILE'] = old_gemfile_setting
    ret
  end

  define_tasks :template_build_ruby18 do
    @facts['runtime'] = 'ruby18'

    install_ruby
    install_ruby_dev
    install_deb "build-essential"

    install_deb "libpq-dev"
    install_deb "libsqlite3-dev"

    install_gem "bundler", {:no_check => true}
  end

  define_tasks :template_build_ruby19 do
    @facts['runtime'] = 'ruby19'

    install_ruby
    install_ruby_dev
    install_deb "build-essential"

    install_deb "libpq-dev"
    install_deb "libsqlite3-dev"

    install_gem "bundler", {:no_check => true}
  end

  define_tasks :install do
    # Can't put these into the class, as we're running in another context.
    known_native_gems = {
      'sqlite3' => {:dev => 'libsqlite3-dev'},
      'sqlite3-ruby' => {:dev => 'libsqlite3-dev'},
      'imagemagick' => {:dev => 'libmagickwand-dev'},
      'rmagick' => {:dev => 'libmagickwand-dev'},
      'pg' => {:dev => 'libpq-dev'},
      'nokogiri' => {:dev => 'libxml2-dev libxslt-dev'},
      'mechanize' => {:dev => 'libxml2-dev libxslt-dev'},
      'mysql' => {:dev => 'libmysqlclient-dev'},
      'mysql2' => {:dev => 'libmysqlclient-dev'},
      'typhoeus' => {:dev => 'libcurl4-openssl-dev'},
      'memcached-northscale' => {:dev => 'libsasl2-dev'},
      'json' => {},
      'yajl' => {},
      'bcrypt-ruby' => {},
      'hpricot' => {},
      'kgio' => {},
      'raindrops' => {},
      'unicorn' => {},
    }

    if [:ruby19, :railsr19].include?(@facts['type'].to_sym)
      @facts['runtime'] = 'ruby19'
    else
      @facts['runtime'] = 'ruby18'
    end

    @facts['app_code'] = $config[:vm_app_code_path]

    # helpfully inject pg/mysql gem, if the service is bound to the app
    # Note: this is duplicated in postinst!
    if @service_config['Postgresql']
      begin
        install_ruby_dev
        install_deb known_native_gems["pg"][:dev] unless known_native_gems["pg"][:dev].nil?
        inject_gem "pg"
      rescue => e
        puts "Exception (ignored) while checking for pg gem: #{e}"
      end
    end
    if @service_config['Mysql']
      begin
        install_ruby_dev
        install_deb known_native_gems["mysql"][:dev] unless known_native_gems["mysql"][:dev].nil?
        inject_gem "mysql"
      rescue => e
        puts "Exception (ignored) while checking for mysql gem: #{e}"
      end
    end

    ruby_wrapper = ""
    gems = []

    if @app_code.files.include?("Gemfile") then
      @app_logger.info "Found Gemfile, using bundler"
      
      # Rails 3 and all other Bundler-using Apps
      ruby_wrapper = "bundle exec"

      if @app_code.files.include?("Gemfile.lock") then
        # with Gemfile.lock, install using --deployment

        begin
          locked = Bundler::LockfileParser.new(@app_code.read_file("Gemfile.lock"))
          locked.specs.each do |spec| gems << spec.name end
          record_hash "Gemfile.lock", Digest::SHA1.hexdigest(@app_code.read_file("Gemfile.lock"))
        rescue => e
          puts "LockfileParser failed #{e}"
          raise e
        end
      end
      if gems == [] then
        # no Gemfile.lock or LockfileParser failed
        @app_code.read_file("Gemfile").split("\n").each do |l|
          l.match(/^\S*gem ['"]([a-zA-Z_\-]+)['"](.*)/) do |m|
            gems << m[1]
          end
        end
        record_hash "Gemfile", Digest::SHA1.hexdigest(@app_code.read_file("Gemfile"))
      end
    elsif @app_code.files.include?("config/environment.rb") then
      # Rails 2.x is too old for Bundler, but still common
      @app_logger.info "Got Rails 2.3 codebase without Gemfile, parsing gems on our own..."
      
      vendored_gem_specs = @app_code.files.select {|f| f[/^vendor\/gems\/[^\/]+\/.specification/] }.map do |specfile|
        Gem::Specification.from_yaml(@app_code.read_file(specfile))
      end
      
      envrb_file = @app_code.read_file("config/environment.rb")
      envrb = envrb_file.split("\n").map {|l| l.split('#').first }.compact.reject {|l| l[/if/] || l[/unless/] }.join("\n")
      envrb = envrb.scan(/^\s*config\.gem ['"]([^'"]*)['"](.*, :version => ['"]([^"']*)['"].*)?$/).map{|g| [g[0], g[2]] }

      dependencies = envrb.map {|name, version| Bundler::Dependency.new(name, version)}
      dependencies += vendored_gem_specs.map {|g| Bundler::Dependency.new(g.name, g.version) }
      
      # We always need to install rack system-wide to avoid unicorn gem installing a too new rack
      vendored_gem_specs.reject! {|g| g.name == 'rack' }
      
      if !@app_code.files.include?("vendor/rails/railties/lib/rails/version.rb")
        rails_version = envrb_file.split("\n").grep(/^RAILS_GEM_VERSION =/)[0].split(/ /)[2].gsub("'","")
        dependencies << Bundler::Dependency.new('rails', rails_version)
      else
        rails_version = @app_code.read_file('vendor/rails/railties/lib/rails/version.rb').match(/MAJOR = (\d+).*MINOR = (\d+).*TINY  = (\d+)/m)[1..3].join('.')
        dependencies << Bundler::Dependency.new('rails', rails_version)
        ['rails', 'activesupport', 'actionpack', 'actionmailer', 'activerecord', 'activeresource'].each do |g|
          vendored_gem_specs << Bundler::RemoteSpecification.new(g, Gem::Version.new(rails_version), Gem::Platform::RUBY, 'http://production.cf.rubygems.org/')
        end
        
        # Install all gems vendored inside the vendored rails, e.g. to avoid rack version conflicts
        ["actionpack/lib/action_controller.rb", "activesupport/lib/active_support/vendor.rb"].each do |f|
          content = @app_code.read_file('vendor/rails/' + f)
          dependencies += content.scan(/^\s*gem ['"]([^'"]*)['"], ['"]([^"']*)['"]$/).map{|g| Bundler::Dependency.new(g[0], g[1]) }
        end
      end

      # Newer Rubygems version require this in combination with rails
      inject_gem "rdoc"

      @app_logger.debug("Gem dependencies:\n" + dependencies.uniq.map {|d| '- ' + d.to_s}.join("\n"))

      specs = []
      ::RecipeTemplate::Ruby.override_bundler('/nowhere', vendored_gem_specs) do
        source = Bundler::Source::Rubygems.new("remotes" => ["http://production.cf.rubygems.org/"])
        definition = Bundler::Definition.new(nil, dependencies, [source], {})
        specs = definition.resolve_remotely!.to_a
        specs.reject! {|s| s.name == 'bundler' }
      end

      specs.each {|spec| gems << spec.name }
      
      (specs - vendored_gem_specs).each do |s|
        inject_gem s.name, s.version.to_s
      end
    else
      # Error?
    end

    # preinstall system libs we already know of
    system_libs = []
    gems.each do |name|
      if known_native_gems.include?(name)
        system_libs << known_native_gems[name][:dev] unless known_native_gems[name][:dev].nil?
      end
    end

    # in the meantime, we can't avoid this, as unicorn isn't prebuilt and has a native ext
    install_ruby_dev
    inject_gem "unicorn"

    if !system_libs.empty? then
      install_deb system_libs
    end

    # gets called by install_injected_gems anyway.
    #bundle_install false
    
    install_injected_gems
    
    if @app_code.files.include?("config/environment.rb") && !@app_code.files.include?("Gemfile")
      # Note: We might have skipped environment.rb gems if they had a condition attached
      #       so we always need to run gems:install (instead of only gems:build)
      rails2_rake_gems("build:force")
      rails2_rake_gems("install")
    end
    
    firststarttask = '# None'
    setuptask = '# None'

    if @app_code.files.include?("config/environment.rb")
      unicorn_bin = ruby_wrapper + ' unicorn_rails'
    else
      unicorn_bin = ruby_wrapper + ' unicorn'
    end

    write_glue({:unicorn_bin => unicorn_bin,
                 :vm_app_code_path => $config[:vm_app_code_path],
                 :vm_app_home => $config[:vm_app_home],
                 :firststarttask => '',
                 :setuptask => ''})

  end

  define_tasks :install_fast do
    begin
      # Note: this is duplicated from install!
      inject_gem "pg" if @service_config['Postgresql']
      inject_gem "mysql" if @service_config['Mysql']
    rescue => e
      puts "Exception (ignored) while injecting gems: #{e}"
    end

    inject_gem "unicorn"

    install_injected_gems
    
    # Build Rails 2.3 vendored gems
    if !@app_code.files.include?("Gemfile") && @app_code.files.include?("config/environment.rb")
      run_cmd "rake gems:build:force", :wd => $config[:vm_app_code_path]
    end
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
      elsif @service_config['Mysql']
        write_database_yml_mysql $config[:vm_app_code_path]+"/config/database.yml", @service_config['Mysql']
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

    if @app_code.files.include?("config/environment.rb") and @app_code.files.include?("config/environments/production.rb") then
      inject_rails_fixes
    end
  end

end
