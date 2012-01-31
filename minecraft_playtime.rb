require_relative 'myfileutils.rb'

module PlaytimeCounter

  class Player
    attr_reader :name, :time, :lifetime_start, :session_start
    def initialize(player_name, logon_time=nil)
      @name = player_name
      @time = 0
      @time_logon = logon_time
      @lifetime_start = logon_time
      @session_start = logon_time
      @last_active = logon_time
      @online = !logon_time.nil?
    end
    
    def online?()
      @online
    end
    
    def logon(t)
      @time_logon = t
      if @lifetime_start.nil? or @time_logon < @lifetime_start
        @lifetime_start = @time_logon
      end
      if @session_start.nil? or @time_logon < @session_start
        @session_start = @time_logon
      end
      @online = true
    end
    
    def logoff(t)
      if @last_active.nil? or t > @last_active
        @last_active = t
      end
      return if @time_logon.nil?
      @time += (t - @time_logon)
      @time_logon = nil
      @session_start = nil
      @online = false
    end
    
    def new_log()
      @time_logon = nil
      @session_start = nil
      @online = false
    end
    
    def end_count()
      if online?
        @time += (Time.now.to_i - @time_logon)
      end
    end
    
    def last_active()
      online? ? Time.now.to_i : @last_active
    end
  end
  
  class Counter
    attr_reader :players
    def initialize(files=[])
      @players = []
      
      unless files.empty?
        files.each do |f|
          add_log(f)
        end
        end_count
      end
    end
    
    def add_log(logfile)
      @players.each { |p| p.new_log }
      
      f = MyFileUtils::FileManager.new(logfile)
      f.each do |line|
        if line.match(/logged in|lost connection/) and line.match(/\[INFO\] [^\s\<\>]+ /) # [INFO] playername
          t = line.match(/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/).to_s
          s = convert_time(t)
          p = line.split(/\s/)[3]
          case line
          when /logged in/
            player_connected(p, s)
          when /lost connection/
            player_disconnected(p, s)
          end
          #puts line if line.match(/DrQ/)
        end
      end
    end
    
    def end_count()
      @players.each { |p| p.end_count }
    end
    
    def array_by_time()
      @players.sort { |x,y| y.time <=> x.time }
    end
    
    def array_by_name()
      @players.sort { |x,y| x.name <=> y.name }
    end
    
    def array_by_lifetime_start()
      @players.sort { |x,y| x.lifetime_start <=> y.lifetime_start }
    end
    
    def array_by_last_activity()
      @players.sort { |x,y| y.last_active <=> x.last_active }
    end
    
    def plot_by_time()
      plot array_by_time()
    end
    
    def plot_by_name()
      plot array_by_name()
    end
    
    def plot_by_lifetime_start()
      plot array_by_lifetime_start()
    end
    
    def plot_by_last_activity()
      plot array_by_last_activity()
    end
    
    def plot(sorted_player_array=@players, sep="  ")
      arr = [["#","Player", "Total Time", "On?", "Session Time", "Session Start", "Last Activity", "First Logon",]]
      
      sorted_player_array.each_with_index do |p, i|
        arr << [
          "#{i+1}",
          "#{p.name}",
          "#{format_time(p.time)}",
          "#{p.online? ? " * " : "" }",
          "#{p.session_start.nil? ? "" : format_time(Time.now.to_i - p.session_start)}",
          "#{format_date(p.session_start)}",
          "#{format_date(p.last_active)}",
          "#{format_date(p.lifetime_start)}", 
        ]
      end
      
      sizes = []
      arr.each do |l|
        l.each_with_index do |s, i|
          if sizes[i].nil? or s.size > sizes[i]
            sizes[i] = s.size
          end
        end
      end
      
      
      sep = "#{sep}"
      out = ""
      arr.each do |l|
        out << l[0].rjust(sizes[0]) << sep
        l.each_with_index do |x, i|
          next if i==0
          out << x.ljust(sizes[i]) << sep
        end
        out << "\r\n"
      end
      
      return out
    end
    
    
    private
    
    def convert_time(str)
      a = str.split(/[\s\-\:]/)
      if a.size > 6
        raise "Bad time string, gave #{a}"
      end
      return Time.local(*a).to_i
    end
    
    def format_time(t)
      f = []
      f[0] = t % 60
      t /= 60
      f[1] = t % 60
      t /= 60
      f[2] = t % 24
      t /= 24
      f[3] = t
      
      f.map! { |x| x.to_s.rjust(2) }
      
      return "#{f[3]}d #{f[2]}h #{f[1]}m #{f[0]}s"
    end
    
    def format_date(d)
      return "" if d.nil?
      t = Time.at(d).localtime.to_s.split(/\s/)
      return "#{t[0]} #{t[1]}"
    end
    
    def player_connected(name, time)
      @players.each do |p|
        if p.name == name
          p.logon(time)
          return
        end
      end
      
      @players.push Player.new(name, time)
    end
    
    def player_disconnected(name, time)
      @players.each do |p|
        if p.name == name
          p.logoff(time)
          return
        end
      end
    end
  end
  
end

if $0 == __FILE__
  include PlaytimeCounter
  puts Counter.new(ARGV).plot_by_time()
end