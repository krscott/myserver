require_relative 'server.rb'

class MockServer < Server
  
  def self.set(*args)
    if args.size == 1
      set_output(*args)
    else
      set_method_output(*args)
    end
  end
  
  def self.set_output(r)
    @@out = r
  end
  
  def self.set_method_output(m, r)
    @@method_out.store(m, r)
  end
  
  def self.calls()
    @@method_calls + []
  end
  
  def self.clear()
    @@out = nil
    @@method_calls = []
    @@method_out = {}
  end
  clear
  
  def self.mock_response(*args)
    args.each do |m|
      define_method(m) do |*a|
        @@method_calls << m
        return (@@method_out[m] or @@out)
      end
    end
  end
  
  mock_response :running?, :start, :stop, :before_backup, :after_backup
end

class DummyServer < MockServer
  @@instance_vars = [:start, :stop, :before_backup, :after_backup].map{|x|"enable_#{x}".to_sym}
  attr_accessor :running, *@@instance_vars
    
  (@@instance_vars).each do |var|
    define_method(var) do
      super
      return instance_variable_get("@#{var}")
    end
  end
  
  def initialize(*args, &block)
    super
    @running = false
    @@instance_vars.each do |var|
      instance_variable_set "@#{var}", true
    end
  end
  
  def running?()
    super
    @running
  end
  
  def start()
    super
    @running = true if @enable_start
    @enable_start
  end
  
  def stop()
    super
    @running = false if @enable_stop
    @enable_stop
  end
end

describe Server, "#new" do
  it "should take a hash argument" do
    Server.new(SERVER_OPTS)
  end
end

describe Server do
  before do
    @server = Server.new(SERVER_OPTS)
  end
  
  it "should have all server options stored" do
    SERVER_OPTS.each do |k,v|
      @server.public_send(k).should == v
    end
  end
  
  it "should know if it's running" do
    @server.should respond_to( :running? )
  end
  
  it "should not be running on startup" do
    @server.running?.should be_false
  end
  
  it "should be able to start" do
    @server.should respond_to(:start)
  end
  
  it "#start should default false" do
    @server.start.should be_false
  end
  
  it "should be able to stop" do
    @server.should respond_to(:stop)
  end
  
  it "#stop should default false" do
    @server.stop.should be_false
  end
  
  it "should be able to prep for backup" do
    @server.should respond_to(:before_backup)
  end
  
  it "#before_backup should default true" do
    @server.before_backup.should be_true
  end
  
  it "should be able to return to normal function after backup" do
    @server.should respond_to(:after_backup)
  end
  
  it "#after_backup should default true" do
    @server.after_backup.should be_true
  end
end

describe ServerManager, "#new" do
  it "should take a Server instance and options hash" do
    ServerManager.new(Server.new, {foo: 1, bar: 2})
  end
end

describe ServerManager, " running MockServer" do
  before do
    MockServer.clear
    @manager = ServerManager.new(MockServer.new(SERVER_OPTS))
  end
  
  it "should be able to store output" do
    @manager.should respond_to(:output)
  end
  
  it "should initially have an empty output string" do
    @manager.output.is_a?(String).should be_true
    @manager.output.empty?.should be_true
  end
  
  it "should be able to put out strings as output (with \\n termination)" do
    @manager.should respond_to(:putout)
    @manager.putout "foo\nbar"
    @manager.output.should == "foo\nbar\n"
  end
  
  it "should be able to dump (and clear) output" do
    @manager.putout "foo\nbar"
    @manager.dumpout.should == "foo\nbar\n"
    @manager.output.empty?.should be_true
  end
  
  it "should store a Server instance" do
    @manager.server.is_a?(Server).should be_true
  end
  
  it "should be able to access Server attributes" do
    SERVER_OPTS.each do |k,v|
      @manager.server.public_send(k).should == v
    end
  end
  
  it "should be able to tell when server is running" do
    MockServer.set(:running?, true)
    @manager.running?.should be_true
  end
  
  it "should be able to tell if server isn't running" do
    MockServer.set(:running?, false)
    @manager.running?.should be_false
  end
  
  it "should generate a status" do
    @manager.should respond_to(:status)
  end
  
  it "should generate a meaningful 'is running' status" do
    MockServer.set(:running?, true)
    @manager.status.should be_true
    @manager.output.empty?.should be_false
    @manager.dumpout.match(/is running/i).should_not be_nil
  end
  
  it "should generate a meaningful 'is not running' status" do
    MockServer.set(:running?, false)
    @manager.status.should be_false
    @manager.output.empty?.should be_false
    @manager.dumpout.match(/(not|n't) running/i).should_not be_nil
  end
  
  it "should be able to start the server" do
    @manager.should respond_to(:start)
    @manager.should respond_to(:run) #alias of start
  end
  
  it "should tell the server to start when not running and #start is called" do
    MockServer.set(:running?, false)
    @manager.start
    MockServer.calls.include?(:start).should be_true
  end
  
  it "shouldn't tell the server to start when already running" do
    MockServer.set(:running?, true)
    @manager.start
    MockServer.calls.include?(:start).should be_false
  end
  
  it "should return Server#running? when #start is called" do
    MockServer.set(:running?, false)
    @manager.start.should be_false
    MockServer.set(:running?, true)
    @manager.start.should be_true
  end
  
  it "should be able to stop the server" do
    @manager.should respond_to(:stop)
  end
  
  it "should tell the server to stop when running and #stop is called" do
    MockServer.set(:running?, true)
    @manager.stop
    MockServer.calls.include?(:stop).should be_true
  end
  
  it "shouldn't tell the server to stop when not running" do
    MockServer.set(:running?, false)
    @manager.stop
    MockServer.calls.include?(:stop).should be_false
  end
  
  it "should return !Server#running? when #stop is called" do
    MockServer.set(:running?, true)
    @manager.stop.should be_false
    MockServer.set(:running?, false)
    @manager.stop.should be_true
  end
  
  it "should be able to restart the server" do
    @manager.should respond_to(:restart)
  end
  
  it "should stop Server before restarting" do
    MockServer.set(:running?, true)
    @manager.restart
    MockServer.calls.include?(:stop).should be_true
  end
  
  it "should start Server again when restarting" do
    MockServer.set(:running?, false)
    @manager.restart
    MockServer.calls.include?(:start).should be_true
  end
  
  it "should be able to back-up server files" do
    @manager.should respond_to(:backup)
  end
  
  it "should prepare Server for backup before backing up" do
    @manager.backup
    MockServer.calls.include?(:before_backup).should be_true
  end
  
  it "should let Server know when backup is complete" do
    @manager.backup
    MockServer.calls.include?(:after_backup).should be_true
  end
  
  it "should be able to restore backed-up files" do
    @manager.should respond_to(:restore)
  end
  
  it "should stop the server to restore backed-up files" do
    @manager.restore
    MockServer.calls.include?(:stop).should be_true
  end
  
  it "should restart the server after restoring from backup." do
    @manager.restore
    MockServer.calls.include?(:start).should be_true
  end
end

describe ServerManager, " (running DummyServer)" do
  before do
    @server = DummyServer.new(SERVER_OPTS)
    @manager = ServerManager.new(@server)
  end
  
  it "should initally not be running" do
    @manager.running?.should be_false
  end
  
  it "should be running after starting" do
    @manager.start
    @manager.running?.should be_true
  end
  
  it "should remain running after re-calling #start" do
    @manager.start
    @manager.start
    @manager.running?.should be_true
  end
  
  it "should not be running after stopping" do
    @manager.stop
    @manager.running?.should be_false
  end
  
  it "should be able to stop running" do
    @manager.start
    @manager.stop
    @manager.running?.should be_false
  end
  
  it "#start should return true when successful" do
    @server.running = false
    @manager.start.should be_true
  end
  
  it "#start should return false when unsuccessful" do
    @server.enable_start = false
    @manager.start.should be_false
  end
  
  it "#start should return true if Server was already running" do
    @server.running = true
    @server.start.should be_true
  end
  
  it "#stop should return true when successful" do
    @server.running = true
    @manager.stop.should be_true
  end
  
  it "#stop should return false when unsuccessful" do
    @server.running = true
    @server.enable_stop = false
    @manager.stop.should be_false
  end
  
  it "#stop should return true if Server was already not running" do
    @server.running = false
    @server.stop.should be_true
  end
  
  it "should call #stop and #start as necessary when restarting" do
    @server.running = true
    @manager.restart
    DummyServer.calls.include?(:stop).should be_true
    DummyServer.calls.include?(:start).should be_true
    @manager.running?.should be_true
  end
  
  it "should call #before_backup and #after_backup as necessary when backing up" do
    @server.running = true
    @manager.backup
    DummyServer.calls.include?(:before_backup).should be_true
    DummyServer.calls.include?(:after_backup).should be_true
    @manager.running?.should be_true
  end
  
  it "should call #stop and #start as necessary when restoring" do
    @server.running = true
    @manager.restore
    DummyServer.calls.include?(:before_backup).should be_true
    DummyServer.calls.include?(:after_backup).should be_true
    @manager.running?.should be_true
  end
end