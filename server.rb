require 'socket'
require_relative 'myfileutils.rb'
require_relative 'myenum.rb'

module MyServer
  # Defaults
  BASE_DIR = File.dirname(__FILE__)
  MD5SUM_SUFFIX = "_md5sum"
  
  SERVER_OPTS = {
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
      cmd "say #{str}" if running?
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
            putout "Created #{@data_dir} backup in #{@last_backup}."
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
          putout "Restored #{@data_dir} from backup '#{@last_restore}'"
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
        puterr "#{data_path} does not exist"
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
end