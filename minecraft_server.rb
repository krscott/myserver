require_relative 'screen_server.rb'

module MyServer
  class MinecraftServer < ScreenServer
    
    private
    
    def invocation()
      "java -Xmx1024M -Xms1024M -jar #{@service} nogui"
    end
  end
  
  class MinecraftManager < ServerManager
    
  end
  
  def self.minecraft_server(*argv)
    server = MinecraftServer.new(SERVER_OPTS)
    manager = MinecraftManager.new(MANAGER_OPTS)
  end
end

if $0 == __FILE__
  MyServer.minecraft_server(*ARGV)
end