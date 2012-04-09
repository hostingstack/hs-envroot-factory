class AppLogger < Logger
  def initialize(log_name)
    @log_name = log_name
    super(nil)
  end

  def add(severity, message = nil, progname = nil, &block)
    severity ||= UNKNOWN
    return true if @level && severity.class != Symbol && severity < @level
    progname ||= @progname
    if message.nil?
      if block_given?
        message = yield
      else
        message = progname
        progname = @progname
      end
    end
    log_name = @log_name
    log_name += ':private' if severity == :private
    message += "\n" unless message[-1] == "\n"[0]
    $redis.rpush log_name, "%s %s" % [severity.to_s.downcase, message]
  end
  def log(severity, message = nil, progname = nil, &block)
    add(severity, message, progname, &block)
  end
end
