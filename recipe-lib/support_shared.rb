class SupportShared
  # Runs cmdline, while yielding new output lines as they come in.
  #
  # Oh the flexibility:
  # cmdline can be a string or an array. Passing a string will run cmdline using a shell.
  # options takes all the same options as Process.spawn, but :out and :err are ignored
  # (they are internally set to a pipe), and :in defaults to /dev/null.
  # To specify an env for Process.spawn, use options[:env].
  #
  # Returns the programs output. Given a block, it will be called whenever full output lines
  # are available. $? is updated.
  def self.spawn(cmdline, options = {})
    r, w = IO.pipe

    options[:in] ||= "/dev/null"
    options[:out] = w
    options[:err] = w
    env = options[:env] || {}
    options.delete(:env)

    pid = Process.spawn(env, *cmdline, options)

    w.close
    output = ""
    buffer = ""

    while Process.waitpid(pid, Process::WNOHANG).nil? do
      result = ""
      begin
        result = r.read_nonblock(8192)
      rescue IO::WaitReadable, Errno::EINTR
        IO.select([r])
        retry
      rescue EOFError
        Process.waitpid(pid)
        break
      end
      output += result
      # only yield full lines
      buffer += result
      last = buffer.rindex("\n")
      if last and block_given?
        yield buffer[0..last]
        buffer = buffer[last+1..-1]
      end
    end
    yield buffer if buffer.length > 0 and block_given?
    output
  end
end
