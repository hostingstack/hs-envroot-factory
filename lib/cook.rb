require 'uri'
require 'erubis'
require 'template_cache'
require 'file_store'
require 'app_logger'
require 'tempfile'
require 'procfile_parser'

class Cook
  class CookPackError < StandardError; end
  class AppRootUploadFailed < StandardError
    def initialize(resp)
      @code = resp.code
    end
    def message
      "Upload failed. Remote server said: #{@code.to_s}"
    end
  end

  def initialize(job_desc)
    @user_uid = 1000
    @user_gid = 1000
    @job_desc = job_desc
    @recipe_serialized_path = "/rr.rb"
    @log_name = 'log:' + @job_desc.job_token
    @app_logger = AppLogger.new @log_name
  end
  
  def generate_recipe
    @app_code = AppCode.new(@job_desc.app_code_url)
    system_facts = {:vm_http_proxy => $config[:vm_http_proxy]}
    @recipe = RecipeGenerator.generate @job_desc.facts, @app_code, @job_desc.service_config, system_facts, @app_logger

    @from_scratch = false
    @from_scratch = true if @recipe.executor_hashed != @job_desc.prev_recipe_hash
    @from_scratch = true if @job_desc.force_from_scratch
  end

  def run(&block)
    # store app config that's determined by ERF-local configuration
    @app_config = {
      :app_code_path => $config[:vm_app_code_path],
      :app_home => $config[:vm_app_home],
      :app_user => $config[:vm_app_user],
      :app_user_uid => @user_uid,
      :app_user_gid => @user_gid,
    }

    log :normal, "Inspecting Code"
    yield "generating recipe" if block_given?
    generate_recipe
    procfile_entries = parse_procfile

    log :normal, "Preparing Virtual Machine"
    yield "prepare_vm" if block_given?
    prepare_vm

    yield "copy_code" if block_given?
    copy_code
    copy_recipe_serialized
    copy_recipe_required_files
    log :normal, "Installing dependencies"
    yield "execute_task_install" if block_given?
    execute_task_install
    yield "execute_task_post_install" if block_given?
    execute_task_post_install
    code_adjust_permissions

    log :normal, "Setting up service proxy"
    setup_serviceproxy
    setup_user_ssh_key

    log :normal, "Cleaning up"
    yield "optimize" if block_given?
    optimize

    log :normal, "Shipping to archive"
    yield "pack" if block_given?
    pack
    yield "ship" if block_given?
    ship

    # expire logs after a day
    $redis.expire @log_name, 86400

    return {
      :recipe_hash => @recipe.executor_hashed,
      :recipe_facts => @recipe.facts,
      :user_ssh_key => @user_ssh_key,
      :app_config => @app_config,
      :procfile_entries => procfile_entries
    }
  rescue StandardError => e
    log :error, e.message
    log :debug, e.backtrace.join("\n") # FIXME: Make private?
    raise
  ensure
    yield "cleanup" if block_given?
    cleanup
    @dest_env_root_file.unlink if @dest_env_root_file
  end

  # Levels: normal, verbose, private
  def log(level, message)
    level = Logger::DEBUG if level == :verbose
    level = Logger::DEBUG if level == :debug
    level = Logger::INFO if level == :normal
    level = Logger::INFO if level == :info
    level = Logger::ERROR if level == :error
    @app_logger.log(level, message)
  end

  def parse_procfile
    begin
      return ProcfileParser.parse! @app_code.read_file("Procfile")
    rescue Errno::ENOENT
      return {}
    end
  end

  def prepare_vm
    if @from_scratch
      template = TemplateCache.get_template_archive(@recipe.template_name)
      @vm = OpenVZ.new_vm template, $config[:vm_id]
    else
      prev_root = fetch_prev_root @job_desc.prev_env_root_url
      @vm = OpenVZ.new_vm prev_root, $config[:vm_id]
    end
    @vm.start
    @vm.add_ip $config[:vm_ip_address]

    # set nameserver from config
    File.open(@vm.path_root + "/etc/resolv.conf", "w") do |f|
      $config[:vm_nameserver].each do |nameserver|
        f.write "nameserver #{nameserver}\n"
      end
    end
  end

  def copy_recipe_serialized
    @recipe_serialized_path_in_target = @vm.path_root + "/" + @recipe_serialized_path
    File.open(@recipe_serialized_path_in_target, "w") do |f|
      f.write @recipe.executor_serialized
    end
  end

  def copy_recipe_required_files
    @recipe.copy_required_files(@vm.path_root)
  end

  def execute_task_install
    task = "install"
    unless @from_scratch
      log :debug, "Fast deploy, using old VM image"
      task = "install_fast"
    end
    @vm.spawn("/usr/bin/ruby1.9.1 " + @recipe_serialized_path + " " + task + " -v") do |lines|
      log :verbose, lines
    end
  end

  def execute_task_post_install
    @vm.spawn("/usr/bin/ruby1.9.1 " + @recipe_serialized_path + " post_install -v") do |lines|
      log :verbose, lines
    end
  end

  def copy_code
    @code_dest = File.expand_path("#{@vm.path_root}/#{$config[:vm_app_code_path]}")
    FileUtils.rm_rf @code_dest # wipe out previously installed version
    FileUtils.mkdir_p @code_dest
    @app_code.unpack(@code_dest)
    code_adjust_permissions
  end

  def code_adjust_permissions
    FileUtils.chown_R @user_uid, @user_gid, @code_dest, :force => true
  end

  def pack
    @dest_env_root_file = Tempfile.new('envroot')
    @dest_env_root_file.close
    cmd = "tar -c --one-file-system -C #{@vm.path_root} ./ 2>&1 | pigz > #{@dest_env_root_file.path} 2>&1"
    log :private, cmd
    output = `#{cmd}`
    log :private, output
    unless $?.exitstatus == 0
      log :private, "ExitStatus: #{$?.exitstatus}"
      raise CookPackError.new
    end
  end

  def setup_user_ssh_key
    dotssh = File.join(@vm.path_root, $config[:vm_app_home], ".ssh")
    FileUtils.rm_rf dotssh
    FileUtils.mkdir_p dotssh
    @vm.exec "ssh-keygen -t rsa -q -f %s -N '' -C app" % File.join($config[:vm_app_home], ".ssh", "id_rsa")
    FileUtils.cp File.join(dotssh, "id_rsa.pub"), File.join(dotssh, "authorized_keys")
    FileUtils.chown_R @user_uid, @user_gid, dotssh, :force => true
    @user_ssh_key = File.read File.join(dotssh, "id_rsa")
  end

  def ship
    log :private, "Uploading \"#{@dest_env_root_file.path}\" to \"#{@job_desc.dest_env_root_url}\""
    File.open(@dest_env_root_file.path, 'r') do |f|
      url = URI.parse(@job_desc.dest_env_root_url)
      Net::HTTP.start(url.host, url.port) do |http|
        req = Net::HTTP::Put.new(@job_desc.dest_env_root_url)
        response = http.request(req, f.read)
        raise AppRootUploadFailed.new(response) unless response.code.to_s == 201.to_s
      end
    end
  end

  def optimize
    if @from_scratch
      @vm.exec "apt-get purge -y build-essential gcc"
      @vm.exec "apt-get autoremove -y --purge"
      @vm.exec "dpkg --purge --force-all apt apt-file apt-utils aptitude dpkg dpkg-dev"
      @vm.exec "rm -rf /var/lib/dpkg /var/lib/apt /var/cache/apt /etc/apt"
      @vm.exec "rm -rf /usr/include /usr/lib/pkgconfig /var/log /tmp/staging"
    end
    @vm.exec "rm -f #{@recipe_serialized_path}"

    # cleanup interfaces file
    File.open("#{@vm.path_root}/etc/network/interfaces", "w") do |f|
      f.write "auto lo\niface lo inet loopback\n"
    end
  end


  def write_serviceproxy_script(file)
    script = <<'EOT'
#!/usr/bin/ruby1.9.1

require 'logger'
require 'socket'

def setup_localhost_src_ip
    wanted_localhost_src_ip = get_src_ip
    run_cmd "ip addr del 127.0.0.1/32 dev venet0", true
    run_cmd "ip addr del 127.0.0.1/32 dev lo", true

    routes = run_cmd "ip route show table 0"
    routes.each_line do |route|
      next unless route.match(/src 127.0.0.1/)
      run_cmd "ip route del #{route}"
    end

    run_cmd "ip route add 127.0.0.1 dev lo src #{wanted_localhost_src_ip}", true
    run_cmd "ip route flush cache"

    if get_src_ip != get_src_ip('127.0.0.1')
      raise "Failed to set src ip address, should be #{wanted_localhost_src_ip} but is #{get_src_ip('127.0.0.1')}"
    end
end

def get_src_ip(dest='8.8.8.8')
    output = run_cmd "ip -o route get #{dest}"
    srcip = output.match(/src\s([^\s]+)/)[1]
    ip = Addrinfo.ip(srcip)
    raise "#{srcip} is probably not an IPv4 address" unless ip.ipv4?
    ip.ip_address
end

def run_cmd(cmd, can_fail=false)
    $logger.debug "Executing #{cmd}"
    output = `#{cmd}`
    $logger.debug "RC: %i" % $?.exitstatus
    rc = $?.exitstatus
    if rc != 0 && can_fail == false
      raise "%s failed with exitstatus %i" % [cmd, rc]
    end
    output
end

def apply_iptables(file="/opt/efc/state/iptables-restore")
    raise "No iptables save file found at %s" % file unless File.exist?(file)
    run_cmd "iptables-restore #{file}"
end

$logger = Logger.new STDOUT

setup_localhost_src_ip
apply_iptables
EOT
    File.open(file, "w") do |f|
      f.write script
      f.chmod(0755)
    end
  end

  def write_serviceproxy_iptables_rules(file)
    template = <<'EOT'
*nat
:PREROUTING ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
<% for rule in rules %>
-A OUTPUT -d 127.0.0.1/32 -p tcp -m tcp --dport <%= rule[:localport]%> -j DNAT --to-destination <%= rule[:destination]%>
<% end %>
COMMIT
EOT

    rules = []
    @job_desc.service_config.each do |service_type,service_config|
      rules << { :localport => service_config["default_local_port"], :destination => "%s:%d" % [service_config["hostname"], service_config["port"]] }
    end
    @app_config[:service_proxy_rules] = rules

    eruby = Erubis::Eruby.new(template)
    iptables_restore_content = eruby.result(binding())
    File.open(file, "w") do |f|
      f.write iptables_restore_content
    end
  end

  def setup_serviceproxy

    FileUtils.mkdir_p @vm.path_root + "/opt/efc/bin"
    write_serviceproxy_script(@vm.path_root + "/opt/efc/bin/setup_service_proxy.rb")

    FileUtils.mkdir_p @vm.path_root + "/opt/efc/state"
    write_serviceproxy_iptables_rules(@vm.path_root + "/opt/efc/state/iptables-restore")
  end

  def cleanup
    unless @vm.nil? then
      @vm.stop
      @vm.destroy
    end
  end

  def fetch_prev_root(prev_root_url)
    uri = URI.parse(prev_root_url)
    tmp = Tempfile.new('prevroot')
    HttpSupport.fetch_file(uri.host, uri.port, uri.path, tmp)
    tmp.close
    tmp.path
  end

end
