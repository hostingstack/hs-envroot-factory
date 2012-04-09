class TemplateArchiveBuilder
  attr_reader :destination, :workdir

  def initialize(opts = {})
    @from_scratch = true
    if opts[:base_template]
      @from_scratch = false
      @base_template = opts[:base_template]
    end
    @destination = opts[:destination]
    @recipe_template_class = opts[:recipe_template_class]
    @template_task = 'template_build'
    @template_task += "_#{opts[:template_flavor]}" if opts[:template_flavor]
    @template_task = @template_task.to_sym
  end

  def build
    Dir.mktmpdir do |workdir|
      @workdir = workdir
      build_internal
    end
  end

  private
  def build_internal
    @destination ||= Tempfile.new('tpl').path
    if @from_scratch
      scratch
    else
      run "tar -C #{@workdir} -xz -f #{@base_template}"
    end
    template_tasks
    cleanup
    pack
  end

  def build_template_recipe
    kls = @recipe_template_class
    facts = {}
    tl = TaskList.new
    tl.instance_variable_set :@facts, facts
    tl.instance_eval &kls.task_blocks[@template_task]
    task_lists = {:build => tl.out}
    kls.recipe_class.new(task_lists, facts, nil, {})
  end

  def template_tasks
    return if @recipe_template_class.nil?
    puts "Running template tasks"
    recipe = build_template_recipe
    
    in_target = "/tpl.rb"
    path_target = @workdir + in_target
    File.open(path_target, "w") do |f|
      f.write recipe.executor_serialized
    end

    recipe.copy_required_files(@workdir)

    chroot "/usr/bin/ruby1.9.1 #{in_target} build -v"

    File.unlink path_target
  end

  def scratch
    distro = $config[:apt_sources].split(" ")[2]
    mirror = $config[:apt_sources].split(" ")[1]
    puts "Working directory: #{workdir}"
    puts "Distribution: #{distro} from Mirror: #{mirror}"

    FileUtils.mkdir_p "#{workdir}/etc/dpkg/dpkg.cfg.d"
    File.open("#{workdir}/etc/dpkg/dpkg.cfg.d/platform", "w") do |f|
      # Note: this only takes effect when dpkg runs inside the chroot,
      # so some stuff must be cleaned up in the cleanup stage below.
      f.write <<-EODPKG
force-unsafe-io
path-exclude=/usr/lib/dri/*
path-exclude=/usr/lib/debug/*
path-exclude=/usr/share/doc/*
path-exclude=/usr/share/ri/*
path-exclude=/usr/share/man/*
path-exclude=/usr/share/locale/*/LC_MESSAGES/*
path-include=/usr/share/locale/*/LC_MESSAGES/libc.mo
      EODPKG
    end

    run "debootstrap --variant=minbase --exclude=udev,whiptail,vim-tiny,vim-common,traceroute,tasksel,tasksel-data,nano,module-init-tools,manpages,logrotate,aptitude,bsdmainutils,cpio,cron,dmidecode,isc-dhcp-client,isc-dhcp-common,rsyslog #{distro} #{@workdir} #{mirror}"

    File.open("#{workdir}/etc/inittab", "w") do |f|
      f.write <<-EOINITTAB
id:2:initdefault:
      EOINITTAB
    end

    File.open("#{workdir}/usr/sbin/policy-rc.d", "w") do |f|
      f.write <<-EOPOLRC
#!/bin/sh
exit 101
      EOPOLRC
    end
    run "chmod a+rx #{workdir}/usr/sbin/policy-rc.d"

    File.open("#{workdir}/etc/locale.gen", "w") do |f|
      f.write <<-EOLOCALE
# factory config
en_US.UTF-8
    EOLOCALE
    end

    # cleanup /etc/profile, especially the PATH
    File.open("#{workdir}/etc/profile", "w") do |f|
      f.write <<-EOPROFILE
if [ "`id -u`" -eq 0 ]; then
  PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
else
  PATH="/usr/local/bin:/usr/bin:/bin"
fi
export PATH

for i in /etc/profile.d/*.sh; do
  if [ -r $i ]; then
    . $i
  fi
done
unset i
    EOPROFILE
    end

    chroot "dpkg-divert --local --rename --add /sbin/init"
    File.open("#{workdir}/sbin/init", "w") do |f|
      f.write <<-EOSYSINIT
#!/bin/sh
export PATH=/usr/sbin:/sbin:/usr/bin:/bin
/etc/init.d/mountdevsubfs.sh start
rm -rf /etc/network/run
mkdir /etc/network/run
ifup -a
exec /sbin/init.distrib
    EOSYSINIT
    end
    run "chmod a+rx #{workdir}/sbin/init"

    File.open("#{workdir}/etc/issue", "w") do |f|
      f.write "HSPlatform"
    end

    File.open("#{workdir}/etc/apt/sources.list", "w") do |f|
      f.write $config[:apt_sources]
    end

    File.open("#{workdir}/bin/startup.ssh", "w") do |f|
      f.write <<-EOSSH
#!/bin/sh
if [ ! -d /var/run/sshd ]; then
  mkdir /var/run/sshd
  chmod 0755 /var/run/sshd
fi
export PATH="/bin:/usr/bin:/usr/sbin:/sbin"
exec /usr/sbin/sshd
    EOSSH
    end
    run "chmod a+rx #{workdir}/bin/startup.ssh"

    chroot "useradd -d #{$config[:vm_app_home]} --uid 1000 -s /bin/bash #{$config[:vm_app_user]}"

    chroot "apt-get update"
    chroot "apt-get install -y --allow-unauthenticated hs-keyring"
    chroot "apt-get update"
    chroot "apt-get install -y --no-install-recommends locales ruby1.9.1 iptables daemontools ifupdown iproute netcat-openbsd telnet procps openssh-server"
  end

  def run(cmd)
    puts cmd
    output = SupportShared.spawn cmd, {:env => {'PATH' => "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin", 'HOME' => '/root'}, :unsetenv_others => true} do |lines|
      prefix = "   "
      puts prefix + lines.split("\n").join("\n" + prefix)
    end
    if $?.exitstatus != 0
      raise "Command exited with rc #{$?.exitstatus}"
    end
  end

  def chroot(cmd)
    run "chroot #{@workdir} #{cmd}"
  end

  def cleanup
    puts "Cleaning up"

    chroot "apt-get clean"
    chroot "dpkg --purge --force-all e2fsprogs"
    chroot "rm -rf /tmp/staging"
    chroot "rm -rf /var/cache/man /etc/issue.net /etc/debian_version /etc/motd.tail /etc/motd /etc/hostname"
    chroot "rm -rf /usr/lib/dri/ /usr/lib/debug/ /usr/share/doc/ /usr/share/ri/ /usr/share/man/"

    chroot "du -sxh / /usr /usr/share /usr/lib /var /var/cache /var/lib"
  end

  def pack
    run "tar -C #{@workdir} -cz -f #{@destination} ."
  end

end
