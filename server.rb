require 'socket'
require_relative 'myruby.rb'

module MyServer
  # Defaults
  BASE_DIR = File.dirname(__FILE__)
  MD5SUM_SUFFIX = "_md5sum"
  
  SERVER_OPTS = {
    output_mode: :quiet,
    server_output_mode: :normal,
    service: "server_executable",
    path: "#{BASE_DIR}",
  }

  SERVER_MANAGER_OPTS = {
    data_dir: "#{BASE_DIR}/data",
    backup_dir: "#{BASE_DIR}/backup",
    update_dir: "#{BASE_DIR}/update",
    update_name: "server_update",
    update_url: nil,
  }
  
  ## Contains methods for communicating with the server software.
  class Server
    attr_reader :output, :hostname, *SERVER_OPTS.keys
    attr_accessor :output_mode, :server_output_mode
    def initialize(h={})
      @output = ""
      @output_mode = :quiet
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
    
    def putout(str)
      puts "#{str}" unless output_mode == :quiet
      host_say "#{str}" unless server_output_mode == :quiet
      output << "#{str}\n"
    end
    
    def puterr(str)
      str = "WARNING: #{str}"
      if output_mode == :error
        puts str
        output << "#{str}\n"
      else
        putout(str)
      end
    end
    
    def cmd(str)
      false
    end
    
    def say(str)
      cmd "say #{str}"
    end
    
    def host_say(str)
      say "#{@hostname}: #{str}"
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
    
    server_attr_accessor :output_mode, :server_output_mode
    server_attr_reader :service, :path
    attr_accessor *SERVER_MANAGER_OPTS.keys
    attr_reader :server, :timestamp, :last_backup, :old_service
    
    def initialize(server, h={})
      @output = ""
      SERVER_MANAGER_OPTS.merge(h).each do |k,v|
        instance_variable_set "@#{k}", v
      end
      @server = server
      
      refresh_timestamp
    end
    
    def refresh_timestamp()
      @timestamp = MyRuby.timestamp
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
          putout "Creating backup of #{service} files..."
          if backup_files
            write_data_md5sum()
            putout "Created #{service} backup in #{@last_backup}."
          else
            puterr "Failed to backup #{service} files."
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
    
    def restore(match_file=/#{File.basename(@data_dir)}/)
      result = false
      was_running = running?
      if stop
        putout "Restoring from backup of #{service} files..."
        if restore_files(match_file)
          putout "Restored #{service} from backup '#{@last_restore}'"
          result = true
        else
          puterr "Failed to restore #{service} files."
        end
        start if was_running
      end
      return result
    end
    
    def update(path=nil)
      result = false
      was_running = running?
      putout "Fetching #{service} update..."
      update_file = (path or fetch_update)
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
        putout "#{service} is running."
      else
        putout "#{service} is not running."
      end
      return running?
    end
    
    def dumpout()
      "#{server.dumpout}"
    end
    
    def putout(str)
      server.putout str
    end
    
    def puterr(str)
      server.puterr str
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
      d = MyRuby::DirectoryManager.new("#{@data_dir}")
      m = MyRuby::FileManager.new(file_backup_md5)
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
      "#{@backup_dir}/#{File.basename(@data_dir)}#{MD5SUM_SUFFIX}"
    end
    
    private
    
    def before_backup()
      true
    end
    
    def after_backup()
      true
    end
    
    def write_data_md5sum()
      @md5sum ||= data_changed?
      m = MyRuby::FileManager.new("#{file_backup_md5}")
      m.write "#{@md5sum}"
    end
    
    def backup_files()
      if !File.directory?(@data_dir)
        puterr "#{@data_dir} does not exist"
        return false
      end
      data = MyRuby::DirectoryManager.new(@data_dir)
      @last_backup = data.create_backup(@backup_dir, @timestamp)
      return @last_backup
    end
    
    def restore_files(match_file=//)
      if !File.directory?(@data_dir)
        puterr "#{@data_dir} does not exist"
        return false
      elsif !File.directory?(@backup_dir)
        puterr "#{@backup_dir} does not exist"
        return false
      end
      data = MyRuby::DirectoryManager.new(@data_dir)
      @last_restore = data.restore_backup(@backup_dir, match_file)
      return @last_restore
    end
    
    def fetch_update()
      return nil if !File.exists?("#{@update_dir}/#{@update_name}")
      return "#{@update_dir}/#{@update_name}"
    end
    
    def service_matches?(file)
      f = MyRuby::FileManager.new(file)
      s = MyRuby::FileManager.new(service_path)
      return (f.md5sum == s.md5sum)
    end
    
    def update_service(update_file)
      srvc = MyRuby::FileManager.new("#{@server.path}/#{@server.service}")
      
      if !File.directory?(@data_dir)
        puterr "#{@data_dir} does not exist"
        return false
      elsif !File.directory?(@backup_dir)
        puterr "#{@backup_dir} does not exist"
        return false
      elsif !File.directory?(@update_dir)
        puterr "#{@update_dir} does not exist"
        return false
      elsif !srvc.exists?
        puterr "Service #{srvc.path} does not exist"
        return false
      end
      
      @old_service = "#{@backup_dir}/#{server.service}#{MyRuby::BACKUP_SEPARATOR}#{@timestamp}"
      old_srvc = MyRuby::FileManager.new(@old_service)
      old_srvc.update(srvc.path)
      srvc.update("#{update_file}")
      return true
    end
  end
end