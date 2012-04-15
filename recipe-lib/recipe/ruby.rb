require 'fileutils'
require 'yaml'

class Recipe::Ruby < Recipe
  def version
    1
  end

  def template_name
    facts['runtime']
  end

  def handle_gem_errors(e)
    handled = false
    generic = {
      /sqlite3.h is missing/ => 'libsqlite3-dev',
      /No pg_config/ => 'libpq-dev',
      /-lmysqlclient... no/ => 'libmysqlclient-dev',
      /libxml2 is missing/ => 'libxml2-dev libxslt-dev',
      /libxslt is missing/ => 'libxslt-dev',
      /Can't find Magick-config/ => 'libmagickwand-dev',
      /imagemagick cannot be found/ => 'libmagickwand-dev',
      /need libcurl/ => 'libcurl4-openssl-dev',
      /error: 'sasl_callback_t' undeclared/ => 'libsasl2-dev',
      /git: not found/ => 'git-core',
    }
    generic.each do |msg, debs|
      if e.message[msg]
        install_ruby_dev
        install_deb debs
        handled = true
      end
    end
    e.message.match(/^Missing the ([a-zA-Z0-9_\-]+) ([0-9\.\-]+)? ?gem/) do |m|
      # Some Rails 2.x apps use this... (Redmine 1.2)
      install_ruby_dev
      if m[2]
        install_gem m[1], {:version => m[2]}
      else
        install_gem m[1]
      end
      handled = true
    end
    e.message.match(/no such file to load -- ([a-zA-Z0-9_\-]+)/) do |m|
      # native extension
      install_ruby_dev
      if m[1] != "mkmf"
        install_gem m[1]
      end
      handled = true
    end
    if e.message[/make: not found/]
      # native extension
      install_ruby_dev
      handled = true
    end


    if not handled
      # collect gem logs
      Dir.glob('/var/lib/gems/**/gem_make.out').each do |fn|
        puts ">>> #{fn} >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
        File.open(fn, 'r') do |f| puts f.read; end
        puts "<<< #{fn} <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<"
      end
      raise "No known remedy for problem:\n#{e}"
    end
  end

  def bundle_install(deployment_mode, tries = 15)
    # patch Gemfile to skip 302 redirects.
    # this causes a massive speedup whem combined with a caching proxy.
    gemfile = facts['app_code'] + '/Gemfile'
    patched = File.read(gemfile).gsub('http://rubygems.org', 'http://production.cf.rubygems.org')
    File.open(gemfile, 'w') do |f|
      f.write patched
    end

    begin
      args = ["bundle", "install", "--no-color"]
      args << "--deployment" if deployment_mode
      run_cmd args, :wd => @app_code_path, :log_msg => "* Running bundler"
    rescue CommandLineError => e
      raise "Retried too often" if tries == 0
      handle_gem_errors(e)
      bundle_install(deployment_mode, tries - 1)
    end
  end

  def install_injected_gems
    gemfile = facts['app_code'] + '/Gemfile'
    if File.exists?(gemfile)
      # With bundler. While everything should have been installed already during normal install,
      # in the fast-path we might have injected a new gem.
      bundle_install false
    else
      # Without bundler.
      @injected_gems ||= []
      @injected_gems.each do |name, version|
        install_gem name, :version => version
      end
    end
  end

  def rails2_rake_gems(gem_cmd, tries = 15)
    begin
      cmd = "rake gems:%s --trace" % gem_cmd
      out = run_cmd cmd, :wd => @app_code_path
      if out[/(ERROR:|Missing the)/]
        raise CommandLineError.new(out, cmd, 0)
      end
    rescue CommandLineError => e
      raise "Retried too often" if tries == 0
      handle_gem_errors(e)
      rails2_rake_gems(gem_cmd, tries - 1)
    end
  end

  def install_gem(name, opts = {})
    if opts[:no_check] != true then
      already_installed = false
      begin
        cmd = "gem list -i #{name}"
        cmd << " -v #{opts[:version]}" unless opts[:version].nil?
        run_cmd cmd, :quiet => true
        already_installed = true
      rescue CommandLineError => e
      end
      return if already_installed
    end

    tries = opts[:tries] || 15
    cmd = "gem install --clear-sources --source http://production.cf.rubygems.org #{name}"
    cmd << " -v #{opts[:version]}" unless opts[:version].nil?
    begin
      run_cmd cmd
    rescue CommandLineError => e
      raise "Retried too often" if tries == 0
      handle_gem_errors(e)
      opts[:tries] = tries - 1
      install_gem(name, opts)
    end
  end

  def install_ruby
    case facts['runtime'].to_sym
    when :ruby19
      install_deb ["ruby1.9.1"]
      # make this ruby the default one
      File.symlink("/usr/bin/ruby1.9.1", "/usr/bin/ruby")
      File.symlink("/usr/bin/irb1.9.1", "/usr/bin/irb")
      File.symlink("/usr/bin/erb1.9.1", "/usr/bin/erb")
      File.unlink("/usr/bin/gem") if File.exists?("/usr/bin/gem")
      File.symlink("/usr/bin/gem1.9.1", "/usr/bin/gem")

      open("/etc/profile", "a") do |f|
        f.puts 'PATH=/var/lib/gems/1.9.1/bin:$PATH'
        f.puts 'export PATH'
      end
      # for the shells we directly spawn ...
      ENV['PATH'] = '/var/lib/gems/1.9.1/bin:' + ENV['PATH']
    when :ruby18
      install_deb ["ruby1.8", "rubygems1.8"]
      # make this ruby the default one
      File.symlink("/usr/bin/ruby1.8", "/usr/bin/ruby")
      File.symlink("/usr/bin/irb1.8", "/usr/bin/irb")
      File.symlink("/usr/bin/erb1.8", "/usr/bin/erb")
      File.unlink("/usr/bin/gem") if File.exists?("/usr/bin/gem")
      File.symlink("/usr/bin/gem1.8", "/usr/bin/gem")

      open("/etc/profile", "a") do |f|
        f.puts 'PATH=/var/lib/gems/1.8/bin:$PATH'
        f.puts 'export PATH'
      end
      # for the shells we directly spawn ...
      ENV['PATH'] = '/var/lib/gems/1.8/bin:' + ENV['PATH']
    else
      raise "unsupported App runtime"
    end

    open(File.expand_path('~/.gemrc'), 'w') do |f|
      f.puts '---'
      f.puts 'gem: --no-ri --no-rdoc -E'
    end
  end

  def install_ruby_dev
    packages = ["build-essential"]
    case facts['runtime'].to_sym
    when :ruby19
      packages << "ruby1.9.1-dev"
    when :ruby18
      packages << "ruby1.8-dev"
    else
      raise "unsupported App runtime"
    end
    install_deb packages
  end

  # inject_gem can be called multiple times (install, postinst), so it needs
  # do to it's own checks.
  def inject_gem(name, version = nil)
    gemfile = facts['app_code'] + '/Gemfile'
    if File.exists?(gemfile)
      return if File.read(gemfile)[/^gem ('|")#{name}('|")/]
      File.open(gemfile, "a") do |f|
        f.puts ''
        if version
          f.puts "gem '#{name}', '#{version}' # injected by platform"
        else
          f.puts "gem '#{name}' # injected by platform"
        end
      end
    else
      @injected_gems ||= []
      @injected_gems << [name, version]
    end
  end

  def write_database_yml_pg(path, dbconfig)
    cfg = {'production' => {
        'adapter' => 'postgresql',
        'encoding' => 'utf8',
        'schema_search_path' => 'public',
        'database' => dbconfig['database'],
        'username' => dbconfig['username'],
        'password' => dbconfig['password'],
        'host' => dbconfig['hostname'],
        'port' => dbconfig['port'],
      }
    }
    file_content path, YAML.dump(cfg)
  end

  def write_database_yml_mysql(path, dbconfig)
    cfg = {'production' => {
        'adapter' => 'mysql',
        'encoding' => 'utf8',
        'schema_search_path' => 'public',
        'database' => dbconfig['database'],
        'username' => dbconfig['username'],
        'password' => dbconfig['password'],
        'host' => dbconfig['hostname'],
        'port' => dbconfig['port'],
      }
    }
    file_content path, YAML.dump(cfg)
  end

  def write_glue(opts = {})
    tpl = <<EOT
#!/bin/sh
export HOME=%vm_app_code_path%
. /etc/profile
rm -f /tmp/log /tmp/unicorn.pid
cd %vm_app_code_path%
. %vm_app_home%/config_vars
if [ "$1" = "first_start" ]; then
  true # keep
  %firststarttask% > /tmp/log 2>&1
fi
%setuptask% >> /tmp/log 2>&1
exec %unicorn_bin% -p 8080 -E production -c /etc/unicorn.conf -D
EOT
    # poor mans erb
    opts.each { |k,v| tpl.gsub!('%'+k.to_s+'%', v) }
    file_content "/bin/startup.real", tpl
    file_chmod "/bin/startup.real", 0755
    file_content "/bin/startup", <<EOT
#!/bin/sh
cd /
exec env - /usr/bin/setuidgid app /bin/startup.real $@
EOT
    file_chmod "/bin/startup", 0755

    file_content "/etc/unicorn.conf", <<EOT
worker_processes 1
listen 8080, :tcp_nopush => true
timeout 30
pid "/tmp/unicorn.pid"
preload_app true
require 'syslog'
class StdForwarder
  def initialize
    # rebind STDOUT
    me = self
    Object.instance_eval {
      remove_const :STDOUT
      const_set :STDOUT, me
      remove_const :STDERR
      const_set :STDERR, me
    }
  end
  def write(data)
    Syslog.log Syslog::LOG_INFO, data.chomp
  end
  def reopen(x); end
  def sync=(x); end
  def flush; end
  def close; end # for logging.rb
end
Syslog.open("unicorn", Syslog::LOG_NDELAY, Syslog::LOG_USER)
$stdout = StdForwarder.new
$stderr = $stdout
GC.respond_to?(:copy_on_write_friendly=) and
  GC.copy_on_write_friendly = true
before_fork do |server, worker|
  defined?(ActiveRecord::Base) and
    ActiveRecord::Base.connection.disconnect!
  sleep 1
end
after_fork do |server, worker|
  defined?(ActiveRecord::Base) and
    ActiveRecord::Base.establish_connection
end
EOT

    file_content "/bin/logcollect", <<EOT
#!/bin/sh
cat /tmp/log
truncate --size=0 /tmp/log
EOT
    file_chmod "/bin/logcollect", 0755

  end

  def inject_rails_plugin(pluginname, content)
    pluginpath = '/app/code/vendor/plugins/' + pluginname
    fpath = pluginpath + '/init.rb'
    if not File.exists?(pluginpath) then
      FileUtils.mkdir_p pluginpath
    end
    if not File.exists?(fpath) then
      puts "* Injecting %s" % pluginname
      File.open(fpath, 'w') do |f|
        f.puts content
      end
    end
  end

  def inject_rails_fixes
    puts "* Rails plugin injection..."

    content = <<-EOT
# injected by platform
# https://github.com/pedro/rails3_serve_static_assets/blob/master/init.rb
# modified to only trigger for Rails3.
case Rails::VERSION::MAJOR
  when 3 then Rails.application.class.config.serve_static_assets = true
end
    EOT
    inject_rails_plugin 'rails_serve_static_assets', content

    content = <<-EOT
# injected by platform
# https://github.com/ddollar/rails_log_stdout/blob/master/init.rb
# modified to use $stdout instead
begin
  def Rails.heroku_stdout_logger
    logger = Logger.new($stdout)
    logger.level = Logger.const_get(([ENV['LOG_LEVEL'].to_s.upcase, "INFO"] & %w[DEBUG INFO WARN ERROR FATAL UNKNOWN]).compact.first)
    logger
  end

  case Rails::VERSION::MAJOR
    when 3 then Rails.logger = Rails.application.config.logger = Rails.heroku_stdout_logger
    when 2 then
      # redefine Rails.logger
      def Rails.logger
        @@logger ||= Rails.heroku_stdout_logger
      end
      %w(
        ActiveSupport::Dependencies
        ActiveRecord::Base
        ActionController::Base
        ActionMailer::Base
        ActionView::Base
        ActiveResource::Base
      ).each do |klass_name|
        begin
          klass = Object
          klass_name.split("::").each { |part| klass = klass.const_get(part) }
          klass.logger = Rails.logger
        rescue
        end
      end
      Rails.cache.logger = Rails.logger rescue nil
  end
rescue Exception => ex
  puts "WARNING: Exception during rails_log_stdout init: %s" % ex.message
end
    EOT
    inject_rails_plugin 'rails_log_stdout', content

  rescue => e
    puts e
  end

end
