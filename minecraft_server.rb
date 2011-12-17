require 'net/http'
require_relative 'screen_server.rb'

# Requires in-script:
UPDATE_ITEMLIST_RB = "itemlist.rb"

CUSTOM_SERVER_OPTS = {
  #path: "#{HOME}/serverfiles",
  path: "/home/minecraft/serverfiles",  # Change this directory as needed.
  service: 'minecraft_server.jar',
}
CUSTOM_MANAGER_OPTS = {
  properties_file: 'server.properties',
  ops_file: 'ops.txt',
  banned_players_list_file: 'banned-players.txt',
  server_log_file: 'server.log',
  itemlist_file: 'itemlist.txt',
  
  players_dir: 'players',
  
  server_log_backup_dir: 'serverlogs',
  
  update_url: "s3.amazonaws.com/MinecraftDownload/launcher/minecraft_server.jar",
  
  world_list: [],
  world_file: '.world',
  
  status_file: '/var/www/mcstatus.txt',
  
  c10t_dir: 'c10t/c10t-HEAD',
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
  nether_dim: 'DIM-1',
  
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
      #@@opts.on("-w", "--world NAME", "Specify a world name.") do |m|
      #  options[:op_world] = m
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
    
    def start()
      if !running?
        save_server_log
        clear_server_log
      end
      super()
    end
    
    def update()
      flag = false
      if @op_item
        update_itemlist
        flag = true
      end
      if @op_service
        super()
        flag = true
      end
      return if flag
      
      # Default
      update_itemlist
      super()
    end
    
    def backup()
      if running?
        cmd "save-all"
        cmd "save-off"
      end
      orig_data_dir = @data_dir
      
      worldlist().each do |w|
        @data_dir = "#{w}"
        super()
      end
      @data_dir = orig_data_dir
      if running?
        cmd "save-on"
      end
    end
    
    def restore(match_file = nil, restore_level = nil)
      
      #if !restore_level.nil? and !Dir.exists?("#{@path}/#{@data_dir})
      #  raise "World data directory '#{restore_level}' does not exist"
      #end
      
      orig_data_dir = @data_dir
      
      @data_dir = (restore_level || world())
      
      if match_file.nil?
        super(/#{@data_dir}\.zip/)
      else
        super(match_file)
      end
      
      #worldlist().each do |w|
      #  @data_dir = "#{w}"
      #  if match_file.nil?
      #    super()
      #  else
      #    super(match_file)
      #  end
      #end
      
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
            draw_map "#{w}/#{@nether_dim}", k, v
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
      return find_item(str, true)
    end
    
    def player(str='')
      find_player(str, true)
    end
    
    def give(p, i, amount=1)
      pl = find_player p
      val = find_item i
      if pl.nil?
        puterr "No player matches '#{p}'", :terminal
        return
      end
      if val.nil?
        puterr "No item matches '#{i}'", :terminal
        return
      end
      if amount.nil? or !amount.to_i.is_a?(Integer)
        puterr "'#{amount}' is not an integer.", :terminal
        return
      end
      c = "give #{pl} #{val} #{amount.to_i}"
      putout c, :terminal
      cmd c
    end
    
    def tp(p1, p2)
      pa = find_player p1
      if pa.nil?
        puterr "No player matches '#{p1}'", :terminal
        return
      end
      
      pb = find_player p2
      if pb.nil?
        puterr "No player matches '#{p2}'", :terminal
        return
      end
      
      c = "tp #{pa} #{pb}"
      putout c, :terminal
      cmd c
    end
    
    def self.command_target_player(*args)
      args.each do |m|
        define_method(m) do |p, *a|
          pl = find_player(p)
          if pl.nil? or pl.empty?
            puterr "No player matches '#{p}'", :terminal
          else
            c = "#{m} #{pl} #{a.join(' ')}"
            putout c, :terminal
            cmd c
          end
        end
      end
    end
    command_target_player :tell, :gamemode, :op, :deop, :kick, :ban, :pardon
    
    
    #######################
    ### PRIVATE METHODS ###
    #######################
    
    private
    
    def find_item(str, termprint=false)
      out = ""
      
      lm = ListMatch.new(itemlist(), term_colors)

      if str.strip.match(/^\d+$/)
        name = itemlist[str]
        if name.nil?
          out << "No item '#{str}' found"
        else
          return str.to_i unless termprint
          out << "#{str} #{name}"
        end
      elsif termprint
        out << lm.match_all(str).join("\n")
        out << "No item '#{str}' found" if out.empty?
      end
      
      putout out, :terminal if termprint
      best = lm.match_best(str)
      if best.is_a? String
        return best.gsub(':','.')
      end
      return best
    end
    
    def find_player(str, termprint=false)
      dir = MyFileUtils::DirectoryManager.new("#{@path}/#{world()}/#{@players_dir}")
      if !dir.exists?
        puterr "Player directory '#{dir.path}' not found", :terminal
        #return nil
      end
      
      players=dir.ls.map{|x| x.sub(/\..*$/,'')}
      lm = ListMatch.new(players)
      
      putout "#{lm.match_all(str).join("\n")}", :terminal if termprint
      return lm.match_best(str) || str
    end

    def update_itemlist()
      putout "Updating item id list", :terminal
      require_relative "#{UPDATE_ITEMLIST_RB}"
      MinecraftItemlist.update("#{@path}/#{@itemlist_file}")
    end
    
    def itemlist()
      return @itemlist unless @itemlist.nil?
      @itemlist = {}
      if !File.exists?("#{@path}/#{@itemlist_file}")
        puterr "#{@itemlist_file} not found. Please run '#{File.basename($0)} update -i'", :terminal
      else      
        text = MyFileUtils::FileManager.new("#{@path}/#{@itemlist_file}").read
        text.split("\n").each do |line|
          @itemlist.store *(line.split("="))
        end
      end
      return @itemlist
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
    
    def clear_server_log()
      log = "#{@path}/#{@server_log_file}"
      if !File.exists?(log)
        puterr "Server log file '#{@server_log_file}' not found"
      else
        FileUtils.rm(log)
      end
    end
    
    def draw_map(level, name, opts="", prefix="")
      if !Dir.exists?("#{@path}/#{level}")
        puterr "World data '#{level}' does not exist", :terminal
        return false
      end

      levelname = level.sub(/\/#{@nether_dim}/,'.nether')
      
      filename = "#{prefix}#{levelname}.#{name}.png".gsub!(/\.+/,'.')
      historyname = "#{prefix}#{levelname}.#{name}.#{timestamp}.png".gsub!(/\.+/,'.')
      
      putout "Drawing map #{filename}", :terminal
      tempimg, sout = c10t(level, opts)
      img = MyFileUtils::FileManager.new( tempimg )
      dest = MyFileUtils::FileManager.new("#{@path}/#{@map_dir}/#{@map_current_dir}/#{filename}")
      if !img.exist?
        puterr "Map #{img.basename} was not created", :terminal
        unless sout.nil?
          putout sout, :terminal
        end
      elsif dest.exists? and dest.md5sum == img.md5sum and !@op_force
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
        FileUtils.rm(img.path)
      end
    end
    
    def draw_google_map(level=nil, opts="")
      level ||= world()
      google_api = "#{@path}/#{@c10t_dir}/#{@c10t_google_api}"
      google_map_dir = "#{@path}/#{@map_dir}/#{@map_google_dir}/google-api-#{level}"
      FileUtils.mkdir_p("#{google_map_dir}/tiles")
      
      putout "Drawing google map of '#{level}'"
      c = "bash -c \"cd #{@path}/#{@c10t_dir} && #{google_api} -w '#{@path}/#{level}' -o '#{google_map_dir}' -O '-M #{@c10t_mb}' #{opts}\""
      
      #c << " > /dev/null" unless @op_verbose
      #system c
      
      output = nil
      if @op_verbose
        # Real-time output
        system c
      else
        # Saved output for later use
        output = `#{c}`
      end
      return output
    end
    
    def c10t(name, opts)
      temppng = "#{@path}/#{@c10t_dir}/output.png"
      if File.exists?(temppng)
        FileUtils.rm(temppng)
      end
      c = "#{@path}/#{@c10t_dir}/#{@c10t} #{opts} -M #{@c10t_mb} -w '#{@path}/#{name}' -o '#{@path}/#{@c10t_dir}/output.png'"
      
      #c << " > /dev/null" unless @op_verbose
      #system c
      
      output = nil
      if @op_verbose
        # Real-time output
        system c
      else
        # Saved output for later use
        output = `#{c}`
      end
      return temppng, output
    end
    
    def world()
      pf = PropertiesFile.new("#{@path}/#{@properties_file}")
      return pf.get("level-name")
    end
    
    def worldlist()
      @world_list ||= []
      @world_list.concat( [world()] ).uniq!
      return @world_list
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
  
  class ListMatch
    def initialize(a, color = true)
      @list = a
      @color = color
    end
    
    def match_all(str)
      arr = []
      best = match_best(str)
      @list.each do |a|
        if k(a) == best and !str.strip.empty?
          arr << "#{all(a)}".tcolor(:green, @color)
        elsif v(a).match(/#{str}/i)
          arr << "#{all(a)}"
        end
      end
      
      return arr
    end
    
    def match_best(str)
      @list.each do |a|
        if v(a).match(/^#{str}$/i)
          return k(a)
        end
      end

      @list.each do |a|
        if v(a).match(/^#{str}/i)
          return k(a)
        end
      end
      
      @list.each do |a|
        if v(a).match(/#{str}/i)
          return k(a)
        end
      end
      return nil
    end

    def all(a)
      return nil if a.nil?
      return a.join(' ') if a.is_a? Array
      return a
    end

    def k(a)
      return nil if a.nil?
      return a[0] if @list.is_a? Hash
      return a
    end

    def v(a)
      return nil if a.nil?
      return a[1] if @list.is_a? Hash
      return a
    end
  end
end

if $0 == __FILE__
  m = MyServer::MinecraftManager.terminal(ARGV, CUSTOM_SERVER_OPTS, CUSTOM_MANAGER_OPTS)
  m.save_status
end
