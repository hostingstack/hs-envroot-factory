require 'uri'
require 'zip/zip'
require 'tempfile'

class AppCode
  attr_accessor :url

  def initialize(url)
    @url = url
    @local_cache = nil
    @local_cache_tmpfile = nil
    @list_cache = nil
  end

  def files
    fetch
    if @list_cache.nil? then
      @list_cache = []
      Zip::ZipFile.foreach(@local_cache) do |e|
        name = e.name.split('/',2).first == @single_root ? e.name.split('/',2).last : e.name
        next if name =~ /__MACOSX/
        next if name.empty?
        @list_cache << name
      end
    end
    @list_cache
  end

  def read_file(name)
    fetch
    realname = @single_root.nil? ? name : (@single_root+'/'+name)
    Zip::ZipFile.open(@local_cache) do |zf|
      zf.get_entry(realname).get_input_stream.read
    end
  end

  def unpack(dest)
    fetch
    Zip::ZipFile.open(@local_cache) do |zf|
      zf.each do |e|
        name = e.name.split('/',2).first == @single_root ? e.name.split('/',2).last : e.name
        next if name =~ /__MACOSX/
        next if name.empty?

        fn = File.expand_path("#{dest}/#{name}")
        raise "Destination \"#{fn}\" not inside \"#{dest}\"" unless fn.starts_with?(dest)
        FileUtils.mkdir_p File.dirname(fn)
        e.extract(fn)
        if (e.unix_perms & 1) == 1 then
          # file is supposed to be executable, make it so
          File.chmod(0755, fn)
        end
      end
    end
  end

  def fetch
    return unless @local_cache.nil?
    uri = URI.parse(@url)
    @local_cache_tmpfile = Tempfile.new('appcode')
    HttpSupport.fetch_file(uri.host, uri.port, uri.path, @local_cache_tmpfile)
    @local_cache = @local_cache_tmpfile.path
    @local_cache_tmpfile.close

    # see if this zip has a single root (assuming folder).
    # if so, the other methods will strip it off
    topdirs = []
    Zip::ZipFile.foreach(@local_cache) do |e| topdirs << e.name.split('/')[0] end
    topdirs.delete('__MACOSX')
    @single_root = topdirs.uniq!.size == 1 ? topdirs.first : nil rescue nil

  rescue
    @local_cache_tmpfile.close if @local_cache_tmpfile
    @single_root = @local_cache = @local_cache_tmpfile = nil
    raise
  end

end
