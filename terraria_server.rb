require 'net/http'
require_relative 'screen_server.rb'

# Requires in-script:
UPDATE_ITEMLIST_RB = "itemlist.rb"

CUSTOM_SERVER_OPTS = {
  #path: "#{HOME}/server",
  path: "/home/terraria/server",  # Change this directory as needed.
  service: 'TerrariaServer.exe',
}
CUSTOM_MANAGER_OPTS = {
  autosave: true,
  
  properties_file: 'serverconfig.txt',
  server_log_file: 'tshock/log.txt',
  
  players_dir: 'players',
  
  server_log_backup_dir: 'serverlogs',
  
  update_url: "https://github.com/downloads/TShock/TShock/TShock%203.4.5.0106.zip", # Placeholder
  
  status_file: '/var/www/terraria_status.txt',
  
  log_dir: 'logs',
}

module MyServer
  class TerrariaServer < ScreenServer
    
    def start()
      cmd "#{invocation}"
      sleep 1
      return running?
    end
    
    def menu()
      cmd "cd #{@path} && mono #{@service}"
      sleep 1
      return running?
    end
    
    def stop()
      cmd "off"
      10.times do
        break if !running?
        sleep 1
      end
      return !running?
    end
    
    private
    
    def invocation()
      "cd #{@path} && mono #{@service} -config #{@properties_file}"
    end
  end
  
  class TerrariaManager < TerminalServerManager
  
    def self.set_opts()
      options = super()
      @@opts.on("-w", "--world NAME", "Specify a world name.") do |m|
        options[:op_world] = m
      end
      @@opts.on("-s","--service [MONO EXECUTABLE]", "Select service") do |x|
        options[:op_service] = (x or true)
      end
      
      return options
    end
    
    def status()
      out = get_status()
      putout out, :terminal
      exit! (running?)
    end
    
    def start()
      if !running?
        save_server_log
        clear_server_log
      end
      super()
    end
    
    def menu()
      if running?
        putout "Server is already running. Run 'menu' instead of 'start' to access menu.", :terminal
      else
        @server.menu()
      end
    end
    
    def save()
      if running?
        putout "Server is saving."
        cmd "save"
      else
        putout "Attempted to save, but server not running", :terminal
      end
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
    
    def world()
      pf = PropertiesFile.new("#{@path}/#{@properties_file}")
      return pf.get("level-name")
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
  t = MyServer::TerrariaManager.terminal(ARGV, CUSTOM_SERVER_OPTS, CUSTOM_MANAGER_OPTS)
  t.save_status
end
