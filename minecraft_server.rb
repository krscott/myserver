require 'net/http'
require_relative 'screen_server.rb'

CUSTOM_SERVER_OPTS = {
  path: '/home/minecraft/serverfiles'
  service: 'minecraft_service.jar'
}
CUSTOM_MANAGER_OPTS = {
  world_list: %w[world world_nether],
  world_file: '.world'
  
  c10t_dir: 'c10t',
  c10t_google_api: 'google-api/google-api.sh',
  c10t_mb: 256,
  
  map_dir: 'maps',
  map_current_dir: 'current',
  map_history_dir: 'history',
  map_google_dir: 'googlemap',
  
  log_dir: 'logs'
}

module MyServer
  class MinecraftServer < ScreenServer
    
    private
    
    def invocation()
      "java -Xmx1024M -Xms1024M -jar #{@service} nogui"
    end
  end
  
  class MinecraftManager < ServerManager
    private
    
    def before_backup(prep_flag=false)
      return unless prep_flag
      if running?
        cmd "save-all"
        cmd "save-off"
      end
    end
    
    def after_backup(prep_flag=false)
      return unless prep_flag
      if running?
        cmd "save-on"
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
    
    def restore(match_file=/#{File.basename(data_path)}/)
      orig_data_dir = @data_dir
      @world_list.each do |w|
        @data_dir = "#{w}"
        super(match_file)
      end
      @data_dir = orig_data_dir
    end
    
    def fetch_update()
      updated_service_path = "#{update_path}/#{service}"
      Net::HTTP.start("s3.amazonaws.com") do |http|
        resp = http.get("/MinecraftDownload/launcher/minecraft_server.jar")
        FileUtils.rm updated_service_path
        open(updated_service_path, "wb") do |f|
          f.write(resp.body)
        end
      end
    end
  end
  
  def self.minecraft_server(*argv)
    server = MinecraftServer.new(CUSTOM_SERVER_OPTS)
    manager = MinecraftManager.new(CUSTOM_MANAGER_OPTS)
    
    manager.public_send(argv.shift, *argv)
  end
end

if $0 == __FILE__
  MyServer.minecraft_server(*ARGV)
end