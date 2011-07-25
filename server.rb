SERVER_OPTS = {
  service: "server_executable",
  path: "#{Dir.pwd}",
  backup_dir: "server_backup",
}

class Server
  attr_reader *SERVER_OPTS.keys
  def initialize(h={})
    h.each do |k,v|
      instance_variable_set "@#{k}", v
    end
  end
  
  def running?()
    false
  end
  
  def start()
    false
  end
  
  def stop()
    false
  end
  
  def before_backup()
    true
  end
  
  def after_backup()
    true
  end
end

class ServerManager
  def self.server_attr_reader(*args)
    args.each do |a|
      define_method(a) do
        @server.public_send(a)
      end
    end
  end
  
  attr_reader :server, :output
  server_attr_reader :service, :path, :backup_dir
  
  def initialize(server, h={})
    @output = ""
    h.each do |k,v|
      instance_variable_set "@#{k}", v
    end
    @server = server
  end
  
  def running?()
    server.running?
  end
  
  def start()
    if running?
      putout "#{service} is already running."
    else
      putout "Starting #{service}..."
      server.start
    end
    return running?
  end
  alias :run :start
  
  def stop()
    if running?
      putout "Stopping #{service}..."
      server.stop
    else
      putout "#{service} isn't running."
    end
    return !running?
  end
  
  def restart()
    stop
    start
  end
  
  def backup()
    putout "Preparing to create backup..."
    ready = server.before_backup
    #puts "READY: #{Server.new.before_backup}, #{MockServer.new.before_backup}"
    if ready
      putout "Creating backup..."
      #backup_files
      server.after_backup
    else
      putout "#{server.class} failed to prepare for backup."
    end
    return ready
  end
  
  def restore()
    server.stop
    putout "Restoring from backup..."
    server.start
  end
  
  def status()
    if running?
      putout "#{service} is running."
    else
      putout "#{service} is not running."
    end
    return running?
  end
  
  def dumpout()
    out = "#{output}"
    output.clear
    return out
  end
  
  def putout(str)
    output << "#{str}\n"
  end
end