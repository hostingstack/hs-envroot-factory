require 'net/http'
require 'uri'

class Module
  def track_subclasses
    instance_eval %{
      def self.known_subclasses
        @__hs_subclasses || []
      end

      def self.add_known_subclass(s)
        superclass.add_known_subclass(s) if superclass.respond_to?(:inherited_tracking_subclasses)
        (@__hs_subclasses ||= []) << s
      end

      def self.inherited_tracking_subclasses(s)
        add_known_subclass(s)
        inherited_not_tracking_subclasses(s)
      end
      alias :inherited_not_tracking_subclasses :inherited
      alias :inherited :inherited_tracking_subclasses
    }
  end
end

# Just collects all methods that are called on it
class TaskList
  def initialize
    @out = []
  end
  
  def method_missing(method, *args, &block)
    @out << [method] + args
  end
  
  def out
    @out
  end
end

class HttpSupport
  def self.fetch_file(hostname, port, path, f)
    res = Net::HTTP.start(hostname, port) do |http|
      http.get(path) do |s|
        f.write(s)
      end
    end
  end
end

class SocketSupport
  def self.local_ip
    orig, Socket.do_not_reverse_lookup = Socket.do_not_reverse_lookup, true  # turn off reverse DNS resolution temporarily

    UDPSocket.open do |s|
      s.connect '192.0.2.1', 1
      s.addr.last
    end
  ensure
    Socket.do_not_reverse_lookup = orig
  end
end
