
CLEAN_AFTER = true

require_relative 'server.rb'
require_relative 'myfileutils.rb'
require_relative 'myenum.rb'

MyServer::SERVER_OPTS[:output_mode] = :quiet;

class Incrementor
  def next()
    @i ||= -1
    @i += 1
  end
end
INCR = Incrementor.new

class MockServer < MyServer::Server
  @@server_methods = [:start, :stop, :cmd, :say]
  @@instance_vars = @@server_methods.map{|x|"enable_#{x}".to_sym}
  attr_accessor :running, *@@instance_vars
    
  @@server_methods.each do |m|
    define_method(m) do |*args, &block|
      super(*args, &block)
      @method_calls << m
      return instance_variable_get("@enable_#{m}")
    end
  end
  
  def calls()
    @method_calls + []
  end
  
  def initialize(*args, &block)
    super
    @method_calls = []
    @running = false
    @@instance_vars.each do |var|
      instance_variable_set "@#{var}", true
    end
  end
  
  def running?()
    super
    @method_calls << :running?
    @running
  end
  
  def start()
    super
    @method_calls << :start
    @running = true if @enable_start
    @running
  end
  
  def stop()
    super
    @method_calls << :stop
    @running = false if @enable_stop
    !@running
  end
end

describe MyServer::Server do
  describe "#new" do
    it "should take a hash argument" do
      MyServer::Server.new({foo: 1, bar: 2})
    end
    
    it "should store hash arguments as instance variables" do
      server = MyServer::Server.new({service: "test service"})
      server.service.should == "test service"
    end
    
    it "should store all server options" do
      server = MyServer::Server.new()
      MyServer::SERVER_OPTS.each do |k,v|
        server.public_send(k).should == v
      end
    end
  end

  describe do
    before do
      @server = MyServer::Server.new()
    end
    
    describe "#output" do
      it "should exist" do
        @server.should respond_to(:output)
      end
    
      it "should initially give an empty output string" do
        @server.output.is_a?(String).should be_true
        @server.output.empty?.should be_true
      end
    end
    
    describe "#output_mode[=]" do
      it "should exist" do
        @server.should respond_to(:output_mode)
        @server.should respond_to(:output_mode=)
      end
      
      it "should store/give output mode symbols" do
        @server.output_mode = :test_output_mode
        @server.output_mode.should == :test_output_mode
      end
    end
    
    describe "#server_output_mode[=]" do
      it "should exist" do
        @server.should respond_to(:server_output_mode)
        @server.should respond_to(:server_output_mode=)
      end
      
      it "should store/give output mode symbols" do
        @server.server_output_mode = :test_output_mode
        @server.server_output_mode.should == :test_output_mode
      end
    end
    
    describe "#putout" do
      it "should exist" do
        @server.should respond_to(:putout)
      end
      
      it "should take a string argument" do
        @server.putout("foo")
      end
      
      it "should be able to put out strings as output (with \\n termination)" do
        @server.putout("foo\nbar")
        @server.output.should == "foo\nbar\n"
      end
    end
    
    describe "#puterr" do
      it "should exist" do
        @server.should respond_to(:puterr)
      end
      
      it "should take a string argument" do
        @server.puterr("foo")
      end
      
      it "should call Server#putout(str)" do
        @server.puterr("foo")
        @server.output.match(/foo/).should be_true
      end
    end
    
    describe "#dumpout" do
      it "should exist" do
        @server.should respond_to(:dumpout)
      end
      
      it "should return output" do
        @server.putout "foo\nbar"
        @server.dumpout.should == "foo\nbar\n"
      end
      
      it "should be clear output after dumping" do
        @server.putout "foo\nbar"
        @server.dumpout
        @server.output.empty?.should be_true
      end
    end
    
    describe "#running" do
      it "should exist" do
        @server.should respond_to( :running? )
      end
      
      it "should not be false on startup" do
        @server.running?.should be_false
      end
    end
    
    describe "#start" do
      it "should exist" do
        @server.should respond_to(:start)
      end
      
      it "should return #running?" do
        @server.start.should == @server.running?
      end
    end
    
    describe "#stop" do
      it "should exist" do
        @server.should respond_to(:stop)
      end
      
      it "should return !#running?" do
        @server.stop.should == !@server.running?
      end
    end
    
    describe "#cmd" do
      it "should exist" do
        @server.should respond_to(:cmd)
      end
      
      it "should take a string argument" do
        @server.cmd("foo")
      end
      
      it "should return false by default" do
        @server.cmd("foo").should be_false
      end
    end
    
    describe "#say" do
      it "should exist" do
        @server.should respond_to(:say)
      end
      
      it "should take a string argument" do
        @server.say("foo")
      end
      
      #it "should return cmd(\"say \#{str}\")" do
      #  @server.say("foo").should == @server.cmd("say foo")
      #end
    end
    
    describe "#host_say" do
      it "should exist" do
        @server.should respond_to(:host_say)
      end
      
      it "should take a string argument" do
        @server.host_say("foo")
      end
    end
  end
end

describe MyServer::ServerManager do
  before :all do
    [:data_dir, :backup_dir, :update_dir, :update_name].each do |k|
      MyServer::SERVER_MANAGER_OPTS[k] << "_test"
    end
    [:service].each do |k|
      MyServer::SERVER_OPTS[k] << "_test"
    end
  end
  
  describe "#new" do
    it "should take a Server instance and options hash" do
      MyServer::ServerManager.new(MyServer::Server.new, {foo: 1, bar: 2})
    end
    
    it "should store hash arguments as instance variables" do
      manager = MyServer::ServerManager.new(MyServer::Server.new,{update_name: "test test"})
      manager.update_name.should == "test test"
    end
    
    it "should store all options" do
      manager = MyServer::ServerManager.new(MyServer::Server.new)
      MyServer::SERVER_MANAGER_OPTS.each do |k,v|
        manager.public_send(k).should == v
      end
    end
  end
  
  describe do
    before do
      @server = MockServer.new()
      @manager = MyServer::ServerManager.new(@server)
    end
  
    after do
      if CLEAN_AFTER
        unless "#{@manager.backup_dir}".empty? or "#{@server.path}".empty?
          Dir.glob("#{@manager.backup_dir}/#{File.basename(@manager.data_dir)}_*.zip").each do |d|
            FileUtils.rm("#{d}")
          end
          Dir.glob("#{@manager.backup_dir}/#{@server.service}_*").each do |d|
            FileUtils.rm("#{d}")
          end
        end
      end
    end
    
    describe "#server" do
      it "should exist" do
        @manager.should respond_to(:server)
      end
      
      it "should hold the child Server" do
        @manager.server.should == @server
      end
      
      it "should be able to access Server attributes" do
        MyServer::SERVER_OPTS.each do |k,v|
          @manager.server.public_send(k).should == v
        end
      end
    end
    
    describe "#output" do
      it "should exist" do
        @manager.should respond_to(:output)
      end
      
      it "should return Server#output" do
        @server.putout "foo\nbar"
        @manager.output.should == "foo\nbar\n"
      end
    end
    
    describe "#output_mode[=]" do
      it "should exist" do
        @manager.should respond_to(:output_mode)
        @manager.should respond_to(:output_mode=)
      end
      
      it "should give Server#output_mode" do
        @server.output_mode = :test_mode
        @manager.output_mode.should == @server.output_mode
      end
      
      it "should relay output mode changes to Server" do
        @manager.output_mode = :test_output_mode
        @manager.output_mode.should == :test_output_mode
        @server.output_mode.should == :test_output_mode
      end
    end
    
    describe "#server_output_mode[=]" do
      it "should exist" do
        @manager.should respond_to(:server_output_mode)
        @manager.should respond_to(:server_output_mode=)
      end
      
      it "should give Server#server_output_mode" do
        @server.output_mode = :test_mode
        @manager.server_output_mode.should == @server.server_output_mode
      end
      
      it "should relay output mode changes to Server" do
        @manager.server_output_mode = :test_output_mode
        @manager.server_output_mode.should == :test_output_mode
        @server.server_output_mode.should == :test_output_mode
      end
    end
    
    describe "#putout" do
      it "should exist" do
        @manager.should respond_to(:putout)
      end
      
      it "should give argument string to child Server#putout" do
        @manager.putout "foo\nbar"
        @manager.output.should == "foo\nbar\n"
        @server.output.should == "foo\nbar\n"
      end
    end
    
    describe "#puterr" do
      it "should exist" do
        @manager.should respond_to(:puterr)
      end
      
      it "should take a string argument" do
        @manager.puterr("foo")
      end
      
      it "should give argument string to child Server#puterr" do
        @manager.puterr("foo")
        @manager.output.match(/foo/).should be_true
        @server.output.match(/foo/).should be_true
      end
    end
    
    describe "#dumpout" do
      before do
        @manager.putout "foo\nbar"
      end
      
      it "should be able to dump output" do
        @manager.dumpout.should == "foo\nbar\n"
      end
      
      it "should clear output after dump" do
        @manager.dumpout
        @manager.output.empty?.should be_true
        @server.output.empty?.should be_true
      end
    end
    
    describe "#running?" do
      it "should exist" do
        @manager.should respond_to( :running? )
      end
      
      it "should return true if server is running" do
        @server.running = true
        @manager.running?.should be_true
      end
      
      it "should return false if server is not running" do
        @server.running = false
        @manager.running?.should be_false
      end
    end
    
    describe "#status" do
      it "should exist" do
        @manager.should respond_to(:status)
      end
      
      it "should generate a meaningful 'is running' status" do
        @server.running = true
        @manager.status.should be_true
        @manager.output.empty?.should be_false
        @manager.dumpout.match(/is running/i).should_not be_nil
      end
      
      it "should generate a meaningful 'is not running' status" do
        @server.running = false
        @manager.status.should be_false
        @manager.output.empty?.should be_false
        @manager.dumpout.match(/(not|n't) running/i).should_not be_nil
      end
    end
    
    describe "#start" do
      it "should exist" do
        @manager.should respond_to(:start)
      end
      
      it "should tell the Server to start" do
        @server.running = false
        @manager.start
        @server.calls.include?(:start).should be_true
      end
      
      it "should not tell the server to start if already running" do
        @server.running = true
        @manager.start
        @server.calls.include?(:start).should be_false
      end
      
      it "should return Server#running? after telling server to start" do
        @server.enable_start = true
        
        @server.running = false
        @manager.start.should be_true
        @server.running = true
        @manager.start.should be_true
        
        @server.enable_start = false
        
        @server.running = false
        @manager.start.should be_false
        @server.running = true
        @manager.start.should be_true
      end
    end
    
    describe "#stop" do
      it "should exist" do
        @manager.should respond_to(:stop)
      end
      
      it "should tell the Server to stop" do
        @server.running = true
        @manager.stop
        @server.calls.include?(:stop).should be_true
      end
      
      it "should not tell the Server to stop if not running" do
        @server.running = false
        @manager.stop
        @server.calls.include?(:stop).should be_false
      end
      
      it "should return !Server#running? after telling server to stop" do
        @server.enable_stop = true
        
        @server.running = true
        @manager.stop.should be_true
        @server.running = false
        @manager.stop.should be_true
        
        @server.enable_stop = false
        
        @server.running = true
        @manager.stop.should be_false
        @server.running = false
        @manager.stop.should be_true
      end
    end
    
    describe "#restart" do
      it "should exist" do
        @manager.should respond_to(:restart)
      end
      
      it "should tell the server to stop" do
        @server.running = true
        @manager.restart
        @server.calls.include?(:stop).should be_true
      end
      
      it "should tell the server to start again after stopping" do
        @server.running = true
        @manager.restart
        @server.calls.include?(:start).should be_true
        @server.running.should be_true
      end
    end
    
    describe "#timestamp" do
      it "should exist" do
        @manager.should respond_to(:timestamp)
      end
    end
    
    describe "#refresh_timestamp" do
      it "should exist" do
        @manager.should respond_to(:refresh_timestamp)
      end
      
      it "should assign a new timestamp" do
        ts = @manager.timestamp
        sleep 1.1
        @manager.refresh_timestamp
        @manager.timestamp.should_not == ts
      end
    end
    
    describe do # Backup/Restore
      
      before do
        @data_basename = "foo/bar/baz.txt"
        @data_file = MyFileUtils::FileManager.new("#{@manager.data_dir}/#{@data_basename}")
        @chaos_str = "#{MyFileUtils.timestamp} #{INCR.next}"
        @data_text = "foo bar #{@chaos_str}"
        @data_file.write(@data_text)
        @timestamp = @manager.timestamp
      end
      
      describe "#backup" do
        it "should exist" do
          @manager.should respond_to(:backup)
        end
        
        it "should successfully backup" do
          @manager.backup.should be_true
          @backup_file = MyFileUtils::ZippedFileManager.new("#{@manager.last_backup}","#{@data_basename}")
          @backup_file.read.should == @data_text
          @backup_file.read.should == @data_file.read
        end
        
        it "should create separate backups for each call" do
          @manager.backup.should be_true
          @backup_file = MyFileUtils::ZippedFileManager.new("#{@manager.last_backup}","#{@data_basename}")
          @backup_file.read.should == @data_text
          @backup_file.read.should == @data_file.read
          
          @data_text = "baz qux #{@chaos_str}"
          @data_file.write(@data_text)
          @manager.backup.should be_true
          @backup_file2 = MyFileUtils::ZippedFileManager.new("#{@manager.last_backup}","#{@data_basename}")
          @backup_file2.should_not == @backup_file
          @backup_file2.read.should == @data_text
          @backup_file2.read.should == @data_file.read
        end
        
        it "should not create a backup if no data has changed" do
          @manager.backup.should be_true
          @backup_file = MyFileUtils::ZippedFileManager.new("#{@manager.last_backup}","#{@data_basename}")
          @backup_file.read.should == @data_text
          @backup_file.read.should == @data_file.read
          
          @manager.backup.should be_true
          @backup_file2 = MyFileUtils::ZippedFileManager.new("#{@manager.last_backup}","#{@data_basename}")
          @backup_file2.read.should == @data_text
          @backup_file2.read.should == @data_file.read
          @backup_file2.should == @backup_file
        end
        
        it "should ensure server is running after backup if previously running" do
          @server.running = true
          @manager.backup.should be_true
          @server.running.should be_true
        end
        
        it "shoudn't start the server if it wasn't running" do
          @server.running = false
          @manager.backup.should be_true
          @server.running.should be_false
        end
      end
      
      describe "#last_backup" do
        it "should exist" do
          @manager.should respond_to(:last_backup)
        end
        
        it "should contain path to last backup" do
          @manager.backup
          bak = @manager.last_backup
          File.exists?(bak).should be_true
          MyFileUtils::ZippedFileManager.new(bak,"#{@data_basename}").read.should == @data_text
        end
      end
      
      describe "#data_changed?" do
        it "should exist" do
          @manager.should respond_to( :data_changed? )
        end
        
        it "should return false if data has not changed since last backup" do
          @manager.backup
          @manager.data_changed?.should be_false
        end
        
        it "should return with md5sum if data has changed since last backup" do
          @manager.backup
          @data_file.append " changed"
          (!!@manager.data_changed?).should be_true
          @manager.data_changed?.match(/^[a-f0-9]+$/).should be_true
        end
      end
      
      describe "#restore" do
        before do
          @manager.backup
          @backup_file = MyFileUtils::ZippedFileManager.new("#{@manager.last_backup}","#{@data_basename}")
        end
        
        it "should exist" do
          @manager.should respond_to(:restore)
        end
        
        it "should restore most recent backup if no args given" do
          @manager.backup
          bad_text = "hi there #{@chaos_str}"
          @data_file.write(bad_text)
          @data_file.read.should == bad_text
          @manager.restore @manager.last_backup
          @data_file.read.should_not == bad_text
          @data_file.read.should == @data_text
        end
        
        it "should be able to selectively restore a backup" do
          text0 = "foo #{@chaos_str}"
          @data_file.write(text0)
          @data_file.read.should == text0
          @manager.backup
          bak0 = @manager.last_backup
          
          text1 = "bar #{@chaos_str}"
          @data_file.write(text1)
          @data_file.read.should == text1
          @manager.backup
          bak1 = @manager.last_backup
          
          text2 = "baz #{@chaos_str}"
          @data_file.write(text2)
          @data_file.read.should == text2
          @manager.backup
          bak2 = @manager.last_backup
          
          text3 = "qux #{@chaos_str}"
          @data_file.write(text3)
          @data_file.read.should == text3
          @manager.backup
          bak3 = @manager.last_backup
          
          @manager.restore bak1
          @data_file.read.should == text1
          @manager.restore bak3
          @data_file.read.should == text3
          @manager.restore bak0
          @data_file.read.should == text0
          @manager.restore bak1
          @data_file.read.should == text1
          @manager.restore bak2
          @data_file.read.should == text2
        end
        
        it "should call Server#stop before restoring" do
          @server.running = true
          @manager.restore
          @server.calls.include?(:stop).should be_true
        end
        
        it "should restart Server after restoring if previoiusly running" do
          @server.running = true
          @manager.restore
          @server.calls.include?(:start).should be_true
          @server.running.should be_true
        end
        
        it "shouldn't restart Server after restoring if previously stopped" do
          @manager.restore
          @server.calls.include?(:start).should be_false
          @server.running.should be_false
        end
        
        it "should not restore files if Server#stop fails" do
          @server.running = true
          @server.enable_stop = false
          @manager.restore
          @server.calls.include?(:start).should be_false
          @server.running.should be_true
        end
      end
    end
    
    describe do # update
      before do
        @service = MyFileUtils::FileManager.new("#{@server.path}/#{@server.service}")
        @service_text = "service executable #{@chaos_str}"
        @service.write(@service_text)
        
        @service_update = MyFileUtils::FileManager.new("#{@manager.update_dir}/#{@manager.update_name}")
        @update_text = "service update #{@chaos_str}"
        @service_update.write(@update_text)
      end
    
      describe "#update" do
        it "should exist" do
          @manager.should respond_to(:update)
        end
        
        it "should restart Server when updating if previously stopped" do
          @server.running = true
          @manager.update
          @server.calls.include?(:stop).should be_true
          @server.calls.include?(:start).should be_true
          @server.running.should be_true
        end
        
        it "shouldn't restart Server after updating if previously stopped" do
          @manager.update
          @server.calls.include?(:start).should be_false
          @server.running.should be_false
        end
        
        it "shouldn't update Server if it failed to stop" do
          @server.running = true
          @server.enable_stop = false
          @manager.update
          @server.calls.include?(:start).should be_false
          @server.running.should be_true
        end
        
        it "should return false if no update exists" do
          # Prevent `rm /`
          "#{@manager.update_dir}".strip.empty?.should be_false
          "#{@manager.update_name}".strip.empty?.should be_false
          FileUtils.rm("#{@manager.update_dir}/#{@manager.update_name}")
          @manager.update.should be_false
        end
        
        it "should update the server executable if it is different" do
          @service.read.should == @service_text
          @manager.update
          @service.read.should_not == @service_text
          @service.read.should == @update_text
        end
        
        it "should not update the server executable if it is the same" do
          @manager.update
          old = @manager.old_service
          @manager.update
          @manager.old_service.should == old
        end
        
        it "should store previous executable in backup" do
          @service.read.should == @service_text
          @manager.update
          old = MyFileUtils::FileManager.new(@manager.old_service)
          old.read.should == @service_text
          old.dir.match(/#{@manager.backup_dir}/).should be_true
        end
      end
      
      describe "#old_service" do
        it "should exist" do
          @manager.should respond_to(:old_service)
        end
        
        it "should contain the old service executable" do
          @manager.update
          old = MyFileUtils::FileManager.new(@manager.old_service)
          old.exists?.should be_true
          old.read.should == @service_text
        end
      end
    end
    
    describe "#cmd" do
      it "should exist" do
        @manager.should respond_to(:cmd)
      end
      
      it "should take a string argument" do
        @manager.cmd("foo")
      end
      
      it "should call Server#cmd" do
        @manager.cmd("foo")
        @server.calls.include?(:cmd).should be_true
      end
    end
    
    describe "#say" do
      it "should exist" do
        @manager.should respond_to(:say)
      end
      
      it "should take a string argument" do
        @manager.say("foo")
      end
      
      it "should call Server#say if running" do
        @server.running = true
        @manager.say("foo")
        @server.calls.include?(:say).should be_true
        @server.calls.include?(:cmd).should be_true
      end
      
      it "should not call Server#say if not running" do
        @server.running = false
        @manager.say("foo")
        @server.calls.include?(:say).should be_false
        @server.calls.include?(:cmd).should be_false
      end
    end
  end
end