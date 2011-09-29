require 'net/http'
require 'rainbow'
require_relative 'screen_server.rb'

UPDATE_ITEMLIST_RB = "itemlist.rb"

CUSTOM_SERVER_OPTS = {
  path: "#{HOME}/serverfiles",
  service: 'minecraft_server.jar',
}
CUSTOM_MANAGER_OPTS = {
  properties_file: 'server.properties',
  ops_file: 'ops.txt',
  banned_players_list_file: 'banned-players.txt',
  server_log_file: 'server.log',
  itemlist_file: 'itemlist.txt',
  
  server_log_backup_dir: 'serverlogs',
  
  update_url: "s3.amazonaws.com/MinecraftDownload/launcher/minecraft_server.jar",
  
  world_list: %w[world world_nether],
  world_file: '.world',
  
  status_file: '/var/www/mcstatus.txt',
  
  c10t_dir: 'c10t/c10t-1.7',
  c10t: 'c10t',
  c10t_google_api: 'google-api/google-api.sh',
  c10t_mb: 256,
  
  map_dir: 'maps',
  map_current_dir: 'current',
  map_history_dir: 'history',
  map_google_dir: 'googlemap',
  
  map_calls: {
    "day" => "",
    "night" => "--night",
    "isometric" => "--isometric",
    "isometric.night" => "--night --isometric",
    "height" => "--heightmap",
  },
  map_hidden_calls: { 
    "cave" => "--cave-mode",
  },
  map_nether_calls: {
    "" => "--hell-mode",
    "isometric" => "--hell-mode --isometric",
  },
  
  log_dir: 'logs',
}

module MyServer
  class MinecraftServer < ScreenServer
    
    def start()
      cmd "#{invocation}"
      sleep 5
      return running?
    end
    
    def stop()
      cmd "stop"
      sleep 10
      return !running?
    end
    
    private
    
    def invocation()
      "cd #{@path} && java -Xmx1024M -Xms1024M -jar #{@service} nogui"
    end
  end
  
  class MinecraftManager < TerminalServerManager
  
    def self.set_opts()
      options = super()
      @@opts.on("-a", "--archive [PATH]", "create archive of operation output") do |p|
        options[:op_archive] = (p or true)
      end
      #@@opts.on("-m", "--map NAME", "Specify a map name.") do |m|
      #  options[:op_name] = m
      #end
      @@opts.on("--googlemap", "create only google map") do |x|
        options[:op_googlemap] = true
      end
      @@opts.on("-i","--item [ID]", "Select item id") do |x|
        options[:op_item] = (x or true)
      end
      @@opts.on("-s","--service [JAR]", "Select service") do |x|
        options[:op_service] = (x or true)
      end
      
      return options
    end
    
    def status()
      out = get_status()
      putout out, :terminal
      return running?
    end
    
    def stop()
      if super()
        save_server_log
      end
    end
    
    def update()
      if @op_item
        update_itemlist
      elsif @op_service
        super()
      else #Default
        update_itemlist
        super()
      end
    end
    
    def backup()
      before_backup(true)
      orig_data_dir = @data_dir
      @world_list.each do |w|
        @data_dir = "#{w}"
        super()
      end
      @data_dir = orig_data_dir
      after_backup(true)
    end
    
    def restore(match_file = /#{File.basename(data_path)}/)
      orig_data_dir = @data_dir
      @world_list.each do |w|
        @data_dir = "#{w}"
        super(match_file)
      end
      @data_dir = orig_data_dir
    end
    
    @@help[:property] = "Lists or sets a property value from server properties file."
    @@help_params[:property] = "[add|remove] [property [value]]"
    def property(*a)
      p = v = op = nil
      case "#{a[0]}"
      when /add/i
        p, v = a[1], a[2]
        op = :add
      when /remove/i
        p, v = a[1], a[2]
        op = :remove
      when /set/i
        p, v = a[1], a[2]
      else
        p, v = a[0], a[1]
      end
      
      pf = PropertiesFile.new("#{@path}/#{@properties_file}")
      if p.nil?
        puts pf.prop_text
      else
        oldv = pf.get(p)
        if v.nil?
          if oldv.nil?
            if op==:add
              pf.set(p,"")
            else
              putout "Could not find property '#{p}'", :terminal
            end
          else
            if op==:remove
              pf.remove(p)
              putout "Removed property '#{p}' with value '#{oldv}'", :terminal
            else
              putout oldv, :terminal
            end
          end
        else
          if oldv.nil?
            if op==:add
              pf.set(p,v)
            else
              putout "Could not find property '#{p}'", :terminal
            end
          else
            pf.set(p,v)
            putout "Changed '#{p}' from '#{oldv}' to '#{pf.get(p)}'", :terminal
          end
        end
        
        return pf.get(p)
      end
      
    end
    [@@help, @@help_params].each { |h| h[:prop] = h[:property] }
    alias :prop :property
    
    @@help[:map] = "Draws the current map. Use no options for default maps."
    @@help_params[:map] = "[-a [ARCHIVE]] [--googlemap] [WORLD] [NAME] [OPTIONS]"
    def map(level=nil, name=nil, opts=nil)
      level ||= @op_map
      opts ||= ""
      
      if running?
        cmd "save-off"
        cmd "save-all"
      end
      
      if !name.nil?
        draw_map(level, name, opts)
      else
        putout "Drawing maps..."
        
        unless @op_googlemap
          w = (level or world())
          @map_calls.each do |k,v|
            draw_map w, k, v
          end
          @map_hidden_calls.each do |k,v|
            draw_map w, k, v, "."
          end
          @map_nether_calls.each do |k,v|
            draw_map "#{w}_nether", k, v
          end
        end
        draw_google_map w
      end
      
      putout "Finished drawing maps!"
      
      if running?
        cmd "save-on"
      end
    end
    
    def save_status()
      out = get_status()
      f = MyFileUtils::FileManager.new(@status_file)
      f.write(out) if f.exists?
    end
    
    def item(*a)
      str = a.join(" ")
      out = ""
      
      #putout find_item(str), :terminal
      #return
      
      get_itemlist if @itemlist.nil?
      if str.match(/\d+/)
        name = @itemlist[str]
        if name.nil?
          out << "No item '#{str}' found"
        else
          out << "#{str} #{name}"
        end
      else
        @itemlist.each do |k,v|
          if v.match(/^#{str}$/i)
            out << "#{k} #{v}\n".color(:green)
          elsif v.match(/#{str}/i)
            out << "#{k} #{v}\n"
          end
        end
        out << "No item '#{str}' found" if out.empty?
      end
      putout out, :terminal
    end
    
    ### PRIVATE ###
    private
    
    def update_itemlist()
      putout "Updating item id list", :terminal
      require_relative "#{UPDATE_ITEMLIST_RB}"
      MinecraftItemlist.update(@itemlist_file)
    end
    
    def get_itemlist()
      @itemlist = {}
      if !File.exists?(@itemlist_file)
        puterr "#{@itemlist_file} not found. Please run '#{File.basename($0)} update -i'", :terminal
      else      
        text = MyFileUtils::FileManager.new(@itemlist_file).read
        text.split("\n").each do |line|
          @itemlist.store *(line.split("="))
        end
      end
      return @itemlist
    end
    
    def find_item(item)
      get_itemlist if @itemlist.nil?
      
      id = @itemlist.key("#{item}")
      return id if !id.nil?
      
      @itemlist.each do |k,v|
        return k if v.match(/^#{item}$/i)
      end
      
      @itemlist.each do |k,v|
        return k if v.match(/#{item}/i)
      end
      
      return nil
    end
    
    def get_status()
      if running?
        return "#{service} is running on world '#{world}'."
      else
        return "#{service} is not running."
      end
    end
    
    def save_server_log()
      log = "#{@path}/#{@server_log_file}"
      if !File.exists?(log)
        puterr "Server log file '#{@server_log_file}' not found"
      else
        FileUtils.mkdir_p("#{@path}/#{@server_log_backup_dir}")
        filename = "#{world()}.#{@server_log_file}.#{@timestamp}.log"
        dest = "#{@path}/#{@server_log_backup_dir}/#{filename}"
        putout "Saving log file '#{@server_log_file}' to #{@server_log_backup_dir}/#{filename}", :terminal
        putout "Saving logs...", :server
        FileUtils.cp(log, dest)
        #MyFileUtils::FileManager.new(log).write("")
      end
    end
    
    def draw_map(level, name, opts="", prefix="")
      if !Dir.exists?("#{@path}/#{level}")
        puterr "World data '#{level}' does not exist", :terminal
      end
      
      filename = "#{prefix}#{level}.#{name}.png".gsub!(/\.+/,'.')
      historyname = "#{prefix}#{level}.#{name}.#{timestamp}.png".gsub!(/\.+/,'.')
      
      putout "Drawing map #{filename}", :terminal
      img = MyFileUtils::FileManager.new( c10t(level, opts) )
      dest = MyFileUtils::FileManager.new("#{@path}/#{@map_dir}/#{@map_current_dir}/#{filename}")
      if !img.exist?
        puterr "Map #{filename} does not exist", :terminal
      elsif dest.exists? and dest.md5sum == img.md5sum
        putout "Map #{filename} hasn't changed", :terminal
      else
        FileUtils.mkdir_p dest.dirname
        FileUtils.cp(img.path, dest.path)
        if @op_archive
          if @op_archive==true
            @op_archive = "#{@path}/#{@map_dir}/#{@map_history_dir}"
          end
          FileUtils.mkdir_p @op_archive
          FileUtils.cp(img.path, "#{@op_archive}/#{historyname}")
        end
      end
    end
    
    def draw_google_map(level=nil, opts="")
      level ||= world()
      google_api = "#{@path}/#{@c10t_dir}/#{@c10t_google_api}"
      google_map_dir = "#{@path}/#{@map_dir}/#{@map_google_dir}/google-api-#{level}"
      FileUtils.mkdir_p("#{google_map_dir}/tiles")
      
      putout "Drawing google map of '#{level}'"
      system("bash -c \"cd #{@path}/#{@c10t_dir} && #{google_api} -w '#{@path}/#{level}' -o '#{google_map_dir}' -O '-M #{@c10t_mb}' #{opts}\"")
    end
    
    def c10t(name, opts)
      system "#{@path}/#{@c10t_dir}/#{@c10t} #{opts} -M #{@c10t_mb} -w '#{@path}/#{name}' -o '#{@path}/#{@c10t_dir}/output.png'"
      return "#{@path}/#{@c10t_dir}/output.png"
    end
    
    def world()
      pf = PropertiesFile.new("#{@path}/#{@properties_file}")
      return pf.get("level-name")
    end
    
    def before_backup(prep_flag=false)
      return true unless prep_flag
      if running?
        cmd "save-all"
        cmd "save-off"
      end
      return true
    end
    
    def after_backup(prep_flag=false)
      return true unless prep_flag
      if running?
        cmd "save-on"
      end
      return true
    end
  end
  
  class PropertiesFile
    attr_reader :props, :comments, :file_manager, :text
    def initialize(file, sep="=", comment="#")
      @sep = sep
      @com = comment
      @file_manager = MyFileUtils::FileManager.new(file)
    end
    
    def get(p)
      read
      return @props[p.to_sym]
    end
    
    def set(p,v)
      @props[p.to_sym] = v.to_s
      write
    end
    
    def remove(p)
      @props.reject! {|k,v| k==p.to_sym}
      write
    end
    
    def read
      @text = @file_manager.read.gsub(/\r/,'')
      @comments = []
      @props = {}
      @text.split(/\n/).each do |l|
        if l.match(/$#{@com}/)
          @comments << l
        elsif l.match(/#{@sep}/)
          a = l.split(@sep)
          a[1] ||= ""
          @props[a[0].to_sym] = a[1]
        end
      end
    end
    
    def write
      @text = ""
      @text << comment_text
      @text << prop_text
      @file_manager.write @text
    end
    
    def comment_text
      read if @comments.nil?
      out = ""
      @comments.each do |c|
        out << "#{c}\n"
      end
      return out
    end
    
    def prop_text
      read if @text.nil?
      out = ""
      @props.each do |k,v|
        out << "#{k}#{@sep}#{v}\n"
      end
      return out
    end
  end
end

if $0 == __FILE__
  m = MyServer::MinecraftManager.terminal(ARGV, CUSTOM_SERVER_OPTS, CUSTOM_MANAGER_OPTS)
  m.save_status
end
