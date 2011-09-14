require_relative 'myruby.rb'
include MyRuby
d = FileManager.new(__FILE__).dir_manager
d.create_archive("#{d.path}/#{d.base}.zip")