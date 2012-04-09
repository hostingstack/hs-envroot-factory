class FileStore

  def self.basedir_for_template(tplname)
    basedir = File.join $config[:file_store], tplname
    FileUtils.mkdir_p basedir
    basedir
  end

  def self.get_template_file(tplname, filename)
    File.join basedir_for_template(tplname), filename
  end

end
