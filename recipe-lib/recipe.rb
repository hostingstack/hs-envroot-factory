require 'digest/sha1'

class Recipe
  attr_reader :tasks, :facts, :system_facts

  def initialize(tasks = {}, facts = {}, app_code_path = nil, system_facts = {})
    @tasks = tasks
    @facts = facts
    @app_code_path = app_code_path
    @system_facts = system_facts

    @cache_installed_debs = []

    @file_staging_area = "/tmp/staging"
  end

  def template_name
    "base"
  end

  def required_files
    files ||= begin
      files = []
      @tasks.each do |stage, steps|
        steps.each do |step|
          files << step[1] if step[0] == :install_file
        end
      end
      files
    end
  end

  def copy_required_files(basedir)
    staging_area = File.join(basedir, @file_staging_area)
    FileUtils.mkdir_p staging_area
    derived_template_name = self.class.name.downcase.gsub(/.*::/,'')
    required_files.each do |filename|
      source = FileStore.get_template_file(template_name, filename)
      source = FileStore.get_template_file(derived_template_name, filename) unless File.exists?(source)
      FileUtils.cp source, staging_area
    end
  end
  
  def execute(name)
    ENV['HTTP_PROXY'] = @system_facts[:vm_http_proxy] unless @system_facts[:vm_http_proxy].nil?
    @tasks[name].each do |t|
      send *t
    end
  end
  
  def serialize
    "#{self.class.name}.new(#{tasks.inspect}, #{facts.inspect}, #{@app_code_path.inspect}, #{@system_facts.inspect})"
  end

  def executor_serialized
    recipe_files = ["support_shared.rb", "recipe.rb"]
    if self.class.name != "Recipe"
      recipe_files << "#{self.class.name.downcase.gsub('::','/')}.rb"
    end

    serialized = ""
    recipe_files.each do |fn|
      serialized << "### #{fn}\n"
      serialized << File.open(File.expand_path("../#{fn}", __FILE__)) do |f| f.read end
      serialized << "\n"
    end
    serialized << "begin\n"
    serialized << "  r = #{self.serialize}.execute ARGV.shift.to_sym\n"
    serialized << "rescue => e\n"
    serialized << '  puts "Build Error: #{e}\n"' + "\n"
    serialized << "  puts e.backtrace if ARGV.shift == '-v'\n"
    serialized << "  Kernel.exit(status=false)\n"
    serialized << "end\n"
    serialized
  end
  
  def executor_hashed
    Digest::SHA1.hexdigest(executor_serialized)
  end

  # Records a file hash in the Recipe.
  # The function body serves no purpose.
  def record_hash(filename, hash)
    # Intentionally left blank.
  end

  def install_deb(packages)
    if packages.class != Array then
      packages = [packages]
    end

    packages = packages.reject do |p|
      @cache_installed_debs.include?(p) || `dpkg-query -s #{p} 2>/dev/null`[/Status:.*installed/]
    end
    return if packages.empty?

    run_cmd "apt-get install -y %s" % packages.join(' ')
    @cache_installed_debs = @cache_installed_debs + packages
  end
  
  def run_cmd(cmdline, opts = {})
    old_wd = Dir.getwd

    Dir.chdir(opts[:wd]) if opts[:wd]
    log_msg = "* Executing \"%s\"" unless opts[:quiet]
    if opts[:log_msg]
      puts opts[:log_msg]
    elsif cmdline === Array
      puts log_msg % cmdline.join(' ') unless opts[:quiet]
    else
      puts log_msg % cmdline unless opts[:quiet]
    end

    output = SupportShared.spawn(cmdline, {:env => {'PATH' => "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin", 'HOME' => '/root'}}) do |lines|
      prefix = "   "
      puts prefix + lines.split("\n").join("\n" + prefix) unless opts[:quiet]
      STDOUT.flush
    end

    unless $?.exitstatus == 0
      raise CommandLineError.new(output, cmdline, $?.exitstatus)
    end

    output
  ensure
    Dir.chdir old_wd
  end

  def install_file(filename, destination)
    FileUtils.cp File.join(@file_staging_area, filename), destination
  end
  
  def file_content(file, tpl, opts = {})
    content = tpl.dup
    opts.each { |k,v| content.gsub!('%'+k.to_s+'%', v) } # poor mans erb
    File.open(file, "w") do |f|
      f.write content
    end
  end

  def file_chmod(file, mode_int)
    File.chmod mode_int, file
  end

  class CommandLineError < StandardError
    attr_reader :cmdline, :exitstatus
    def initialize(message, cmdline, exitstatus)
      super(message)
    end
  end
end
