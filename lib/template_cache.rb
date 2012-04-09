require 'template_archive_builder'
require 'file_store'

class TemplateCache

  def self.basedir_for_template(tplname)
    basedir = File.join $config[:template_cache], tplname
    FileUtils.mkdir_p basedir
    basedir
  end

  def self.get_template_file(tplname, filename)
    File.join basedir_for_template(tplname), filename
  end

  def self.get_template_archive(tplname)
    get_template_file tplname, 'template.tgz'
  end

  def self.add_template_file(tplname, filename, tempname)
    path = File.join basedir_for_template(tplname), filename
    File.rename tempname, path
  end

  def self.add_template_archive(tplname, tempname)
    add_template_file(tplname, 'template.tgz', tempname)
  end

  def self.stamp_cache_version
    File.open(File.join($config[:template_cache], 'version.txt'), 'w') do |f|
      f.write(EnvrootFactoryVersion)
    end
  end

  def self.get_cache_version
    File.read(File.join($config[:template_cache], 'version.txt')).strip
  rescue Errno::ENOENT
    ""
  end

  def self.build_template(name, opts = {})
    puts ">>>BUILD>>>#{name}>>>#{opts.inspect}"
    opts[:destination] = Tempfile.new('tpl', TemplateCache.basedir_for_template(name)).path
    builder = TemplateArchiveBuilder.new opts
    builder.build
    TemplateCache.add_template_archive name, builder.destination
  end

  def self.get_all_template_names
    all = ['base']
    RecipeTemplate.known_subclasses.each do |kls|
      next if kls.templates.nil?
      kls.templates.each do |name|
        all << name.to_s
      end
    end
    all
  end

  def self.verify_all_template_archives_exist
    return false if get_cache_version != EnvrootFactoryVersion
    get_all_template_names.each do |name|
      if !File.exists?(TemplateCache.get_template_archive(name))
        return false
      end
    end
  end

  def self.rebuild_all_template_archives(opts = {})
    stamp_cache_version
    build_template 'base' unless opts[:skip_base]
    RecipeTemplate.known_subclasses.each do |kls|
      opts = {
        :base_template => TemplateCache.get_template_archive('base'),
        :recipe_template_class => kls
      }
      next if kls.templates.nil?
      kls.templates.each do |name|
        opts[:template_flavor] = name
        build_template name.to_s, opts
      end
    end
  end
end
