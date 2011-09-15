require_relative 'server.rb'

module MyServer
  class ScreenServer < Server
    attr_writer :service
    
    def initialize(h={})
      super
      @sockname ||= self.class.to_s
      @window ||= @sockname
    end
    
    def service()
      raise "#Service not initialized" if @service.nil?
      return @service
    end
    
    def running?()
      system "ps ax | grep -v grep | grep -v -i SCREEN | grep #{service} > /dev/null"
    end
    
    def cmd(str)
      start_screen unless screen_running?
      # bash$ screen -S "$SOCKNAME" -p "$WINDOW" -X eval "stuff \"$1\"\015"
      system "screen -S #{@sockname} -p #{@window} -X eval \"stuff \\\"#{str}\\\"\\\015\""
    end
    
    private
    
    def screen_running?()
      system "screen -ls | grep #{@sockname} > /dev/null"
    end
    
    def start_screen()
      system "screen -dmS #{@sockname} -t #{@window}"
      putout "Creating new screen session. Socket name: #{@sockname}; Window: #{@window}"
    end
  end
end