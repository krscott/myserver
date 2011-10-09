require 'socket'
require 'optparse'
require 'rainbow'
require_relative 'myfileutils.rb'
require_relative 'myenum.rb'

class String
  def tcolor(c, check=true)
    check && !!c ? self.color(c) : self
  end
end

module MyServer
  # Defaults
  BASE_DIR = File.dirname(__FILE__)
  MD5SUM_SUFFIX = "_md5sum"
  
  SERVER_OPTS = {
    term_colors: true,
    output_save_length: 1000,
    output_mode: :normal,
    server_output_mode: :normal,
    service: "server_executable",
    path: "#{BASE_DIR}",
  }

  SERVER_MANAGER_OPTS = {
    data_dir: "data",
    backup_dir: "backup",
    update_dir: "update",
    update_name: "server_update",
    update_url: nil,
  }
  
  USAGE = 'Usage: #{File.basename($0)} COMMAND [OPTIONS]'
  
  HELP_TEXT = 'Commands
    start                            start the server
    stop                             stop the server
    restart                          stop and start the server
    update                           update #{service}
    backup                           backup #{service} data
    restore [PATTERN]                restore data from backup 
                                       (default: last backup)
    status                           display server status
    help                             display this help
    cmd COMMAND                      send a command to server
    say TEXT                         broadcast a message to players'
  
  ## Contains methods for communicating with the server software.
  class Server
    attr_reader :output, :hostname, *SERVER_OPTS.keys
    attr_accessor :output_mode, :server_output_mode
    def initialize(h={})
      @output = ""
      SERVER_OPTS.merge(h).each do |k,v|
        instance_variable_set "@#{k}", v
      end
      @hostname = Socket.gethostname
    end
    
    def running?()
      false
    end
    
    def start()
      return running?
    end
    
    def stop()
      return !running?
    end
    
    def dumpout()
      out = "#{output}"
      output.clear
      return out
    end
    
    def putout(str, mode=:all, color=nil)
      if mode == :all or mode == :terminal
        puts str.tcolor(color, @term_colors) unless output_mode == :quiet
        #append_output "#{str}\n"
      end
      
      if mode == :all or mode == :server
        host_say "#{str}" unless server_output_mode == :quiet
      end
    end
    
    def puterr(str, mode=:all, color=nil)
      color ||= :yellow
      str = "WARNING: #{str}"
      if output_mode == :error
        puts "#{str.tcolor(color, @term_colors)}"
        #append_output "#{str}\n"
      else
        putout(str, mode, color)
      end
    end
    
    def cmd(str)
      false
    end
    
    def say(str)
      cmd "say #{str}" if running?
    end
    
    def host_say(str)
      say "#{@hostname}: #{str}"
    end
    
    private
    
    def append_output(str)
      output << "#{str}\n"
      while output.length > @output_save_length
        output.sub!(/$[^\n]\n/,'')
      end
    end
  end
  
  ## Manages the Server class at a higher level.
  ## Never calls the server software directly.
  class ServerManager
    def self.server_attr_reader(*args)
      args.each do |a|
        define_method(a) do
          @server.public_send(a)
        end
      end
    end
    def self.server_attr_writer(*args)
      args.each do |a|
        meth = "#{a}=".to_sym
        define_method(meth) do |v|
          @server.public_send(meth, v)
        end
      end
    end
    def self.server_attr_accessor(*args)
      args.each do |a|
        server_attr_reader(a)
        server_attr_writer(a)
      end
    end
    
    server_attr_accessor :output_mode, :server_output_mode, :optparser
    server_attr_reader :service, :path, :timestamp
    attr_accessor *SERVER_MANAGER_OPTS.keys
    attr_reader :server, :timestamp, :last_backup, :old_service
    
    def initialize(server, h={})
      @output = ""
      SERVER_MANAGER_OPTS.merge(h).each do |k,v|
        instance_variable_set "@#{k}", v
      end
      @server = server
      
      @path = @server.path
      
      [@path, data_path, update_path, backup_path].each do |p|
        FileUtils.mkdir_p(p)
      end
      
      refresh_timestamp
    end
    
    def refresh_timestamp()
      @timestamp = MyFileUtils.timestamp
    end
    
    def service_path()
      "#{@path}/#{@service}"
    end
    
    def data_path()
      "#{@path}/#{@data_dir}"
    end
    
    def update_path()
      "#{@path}/#{@update_dir}"
    end
    
    def backup_path()
      "#{@path}/#{@backup_dir}"
    end
    
    def term_colors()
      server.term_colors
    end
    
    def usage()
      eval "puts \"#{USAGE}\""
    end
    
    def help()
      usage
      eval "puts \"#{HELP_TEXT}\""
    end
    
    def running?()
      server.running?
    end
    
    def start()
      if running?
        putout "Attempted to start #{service}, but it's already running."
      else
        putout "Starting #{service}..."
        server.start
      end
      result = running?
      if !result
        puterr "Could not start #{service}."
      end
      return result
    end
    alias :run :start
    
    def stop()
      if running?
        putout "Stopping #{service}..."
        server.stop
      else
        putout "Attempted to stop #{service}, but it isn't running."
      end
      result = !running?
      if !result
        puterr "Could not stop #{service}."
      end
      return result
    end
    
    def restart()
      stop if running?
      start if !running?
    end
    
    def backup()
      result = false
      if before_backup
        if data_changed?
          putout "Creating backup of #{@data_dir} files..."
          if backup_files
            write_data_md5sum()
            putout "Created #{@data_dir} backup in #{@last_backup}.", :terminal
            putout "Created #{@data_dir} backup in #{File.basename(@last_backup)}.", :server
          else
            puterr "Failed to backup #{@data_dir} files."
          end
        else
          putout "Data has not changed. Backup aborted."
        end
        if after_backup
          result = true
        else
          puterr "#{self.class} failed post-backup routine."
        end
      else
        puterr "#{self.class} failed to prepare for backup. Backup aborted."
      end
      return result
    end
    
    def restore(match_file=/#{File.basename(data_path)}/)
      result = false
      was_running = running?
      if stop
        putout "Restoring from backup of #{@data_dir} files..."
        if restore_files(match_file)
          putout "Restored #{@data_dir} from backup '#{@last_restore}'", :terminal
          putout "Restored #{@data_dir} from backup '#{File.basename(@last_restore)}'", :server
          result = true
        else
          puterr "Failed to restore #{@data_dir} files."
        end
        start if was_running
      end
      return result
    end
    
    def update(custom_path=nil)
      result = false
      was_running = running?
      putout "Fetching #{service} update..."
      update_file = (custom_path or fetch_update)
      if update_file.nil?
        puterr "Unable to fetch #{service} update."
      elsif !File.exists?(update_file)
        puterr "#{update_file} does not exist."
      elsif service_matches?(update_file)
        putout "#{service} already up to date."
      elsif stop
        backup
        putout "Updating..."
        if update_service(update_file)
          putout "#{service} updated successfully."
          result = true
        else
          puterr "#{service} update failed."
        end
        start if was_running
      end
      return result
    end
    
    def status()
      if running?
        putout "#{service} is running.", :terminal
      else
        putout "#{service} is not running.", :terminal
      end
      return running?
    end
    
    def dumpout()
      "#{server.dumpout}"
    end
    
    def putout(*a)
      server.putout *a
    end
    
    def puterr(*a)
      server.puterr *a
    end
    
    def output()
      "#{server.output}"
    end
    
    def cmd(str)
      server.cmd(str)
    end
    
    def say(str)
      server.say(str) if running?
    end
    
    def data_changed?()
      return true if !Dir.exists?("#{data_path}")
      d = MyFileUtils::DirectoryManager.new("#{data_path}")
      m = MyFileUtils::FileManager.new(file_backup_md5)
      @md5sum = d.md5sum
      if m.exists? and m.read == @md5sum
        return false
      else
        return @md5sum
      end
    end
    
    def service_changed?(update_file=nil)
      update_file ||= fetch_update
      return service_matches?(update_file)
    end
    
    def service_path()
      out = "#{@server.path}".strip
      out << "/" unless out.empty?
      out << "#{@server.service}"
      return out
    end
    
    def file_backup_md5()
      "#{backup_path}/#{File.basename(data_path)}#{MD5SUM_SUFFIX}"
    end
    
    ##### PRIVATE METHODS #####
    private
    
    def before_backup()
      true
    end
    
    def after_backup()
      true
    end
    
    def write_data_md5sum()
      @md5sum ||= data_changed?
      m = MyFileUtils::FileManager.new("#{file_backup_md5}")
      m.write "#{@md5sum}"
    end
    
    def backup_files()
      if !File.directory?(data_path)
        puterr "#{data_path} does not exist", :terminal
        return false
      end
      data = MyFileUtils::DirectoryManager.new(data_path)
      @last_backup = data.create_backup(backup_path, @timestamp)
      return @last_backup
    end
    
    def restore_files(match_file=//)
      if !File.directory?(data_path)
        puterr "#{data_path} does not exist"
        return false
      elsif !File.directory?(backup_path)
        puterr "#{backup_path} does not exist"
        return false
      end
      data = MyFileUtils::DirectoryManager.new(data_path)
      @last_restore = data.restore_backup(backup_path, match_file)
      return @last_restore
    end
    
    def fetch_update()
      if @update_url.nil?
        return nil if !File.exists?("#{update_path}/#{@update_name}")
        return "#{update_path}/#{@update_name}"
      else
        updated_service_path = "#{update_path}/#{service}"
        return MyFileUtils.download(@update_url, updated_service_path)
      end
    end
    
    def service_matches?(file)
      f = MyFileUtils::FileManager.new(file)
      s = MyFileUtils::FileManager.new(service_path)
      return false if (!f.exists? || !s.exists?)
      return (f.md5sum == s.md5sum)
    end
    
    def update_service(update_file)
      srvc = MyFileUtils::FileManager.new("#{server.path}/#{server.service}")
      
      if !File.directory?(data_path)
        puterr "#{data_path} does not exist"
        return false
      elsif !File.directory?(backup_path)
        puterr "#{backup_path} does not exist"
        return false
      elsif !File.directory?(update_path)
        puterr "#{update_path} does not exist"
        return false
      end
      
      if srvc.exists?
        putout "Creating backup of old #{server.service}"
        @old_service = "#{backup_path}/#{server.service}#{MyFileUtils::BACKUP_SEPARATOR}#{@timestamp}"
        old_srvc = MyFileUtils::FileManager.new(@old_service)
        old_srvc.update(srvc.path)
      end
      
      srvc.update("#{update_file}")
      return true
    end
  end
  
  class TerminalServerManager < ServerManager
    
    def self.terminal(argv, server_opts, manager_opts)
      
      optparse_options = set_opts()
      parse_opts(argv)
      manager_opts.merge!(optparse_options)
      
      server = MinecraftServer.new(server_opts)
      manager = MinecraftManager.new(server, manager_opts)
      
      if argv.empty?
        manager.usage
      else
        method = argv.shift
        begin
          manager.public_send(method, *argv)
        rescue Exception => e
          puts "#{e.class}: #{e.message}".tcolor(:red, manager.term_colors)
          if e.class == NoMethodError and !manager.methods.include?(method.to_sym)
            manager.help
          else
            puts e.backtrace.map{|x| "  #{x}"}
          end
        end
      end
      
      return manager
    end 
    
    def self.set_opts()
      options = {}
      
      @@opts ||= OptionParser.new
      @@opts.banner = "\nMore Options"
      @@opts.on("-f", "--force", "try harder!") { options[:op_force] = true }
      @@opts.on("-v", "--verbose", "Print more output.") { options[:op_verbose] = true }
      @@opts.on("-h", "--help [METHOD]", "display in-depth help [about METHOD]") do |x|
        options[:op_help] = (x or true)
      end
      
      return options
    end
    
    def self.parse_opts(args=ARGV)
      @@opts.parse! args
    end
    
    [:cmd, :say].each do |m|
      define_method(m) do |*a|
        if a.empty?
          super()
        else
          super(a.join(" "))
        end
      end
    end
    
    @@help_params = {}
    
    @@help = {
      help: "I think you can figure this one out.",
      start: "Starts the server",
      stop: "Stops the server",
      restart: "Restarts the server",
    }
    
    def initialize(*a)
      super(*a)
      if @op_help
        begin
          if @op_help==true and !ARGV[0].nil? and !ARGV[0].empty? and methods.include?(ARGV[0].to_sym)
            @op_help = ARGV[0]
          end
          if @op_help.is_a? String and @@help.keys.include?(@op_help.to_sym)
            puts "Usage: #{File.basename($0)} #{@op_help} #{@@help_params[@op_help.to_sym]}"
            puts "  #{@@help[@op_help.to_sym]}"
          else
            help
            puts @@opts
          end
        ensure
          # Don't want any runaway commands
          exit
        end
      end
    end
    
  end
end
