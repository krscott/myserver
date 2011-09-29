require 'rubygems'
require 'mechanize'
require_relative 'myfileutils.rb'

module MinecraftItemlist
  
  URL = 'http://minecraft-ids.grahamedgecombe.com/'
  SEP = "="
  
  def self.list()
    agent = Mechanize.new
    page = agent.get URL
    items = {}
    page.links.each do |l|
      if (l.href.match /\/items\/\d+/)
        items[l.href.match(/\d+[^\/]*/).to_s.strip] = l.text.strip
      end
    end
    
    return items
  end
  
  def self.update(file)
    items = list()
    out = ""
    
    items.each do |k,v|
      out << "#{k}#{SEP}#{v}\n"
    end
    
    MyFileUtils::FileManager.new(file).write out
  end
end