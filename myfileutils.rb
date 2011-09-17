require 'fileutils'
require 'zip/zip'
require 'zip/zipfilesystem'
require 'digest/md5'

module MyFileUtils
  
  BACKUP_SEPARATOR = "_"
  
  def self.timestamp()
    # "YYYYMMDD_hhmmss"
    Time.new.to_a[0..5].reverse.insert(3,"_").map{|x| x.is_a?(String) ? x : x.to_s.rjust(2,"0")}.join("")
  end
  
  def self.download(from, to)
    host = from.match(/^[^\/]*/).to_s
    dir = from.match(/\/.*/).to_s
    FileUtils.mkdir_p File.realpath(File.dirname(to))
    puts File.realpath(File.dirname(to))
    Net::HTTP.start(host) do |http|
      resp = http.get(dir)
      #FileUtils.rm to
      open(to, "wb") do |f|
        f.write(resp.body)
      end
    end
    return to
  end
  
  class DirectoryManager
    attr_reader :dir
    
    def initialize(directory=Dir.pwd)
      @dir = File.realpath(directory)
    end
    
    def realpath()
      @dir
    end
    alias :path :realpath
    
    def basename()
      File.basename(@dir)
    end
    alias :base :basename
    
    def each(*args, &block)
      Dir.glob("#{path}/*").each(*args, &block)
    end
    
    def parent()
      self.class.new(File.dirname(@dir))
    end
    
    def children()
      Dir.glob("#{dir}/*").map do |x|
        if File.directory?(x)
          self.class.new(x)
        else
          FileManager.new(x)
        end
      end
    end
    
    def tree(*opts)
      opts << [:file, :dir] if opts.empty?
      out = []
      out << path if opts.include?(:dir) and !opts.include?(:child)
      opts.reject!{|o| o==:child}
      children.each { |c| 
        if c.is_a?(DirectoryManager)
          out << c.tree(*opts)
        elsif opts.include? :file
          out << c.path
        end
      }
      return out.flatten.compact
    end
    
    def ls()
      children.map do |d|
        d.inspect.sub(/#{@dir}\//,'')
      end
    end
    
    def cd(newdir)
      if Dir.exists?("#{dir}/#{newdir}")
        @dir = File.realpath("#{dir}/#{newdir}")
      elsif Dir.exists?(File.realpath(newdir)) and File.realpath(newdir)==newdir
        @dir = File.realpath(newdir)
      end
    end
    
    def md5sum()
      sums = []
      children.each do |f|
        sums << "#{f.md5sum}"
      end
      sums.sort!
      return Digest::MD5.hexdigest(sums.join(''))
    end
    
    def create_backup(backup_dir=parent.dir, stamp=MyRuby.timestamp())
      ext = ".zip"
      
      FileUtils.mkdir_p(backup_dir)
      
      b = "#{BACKUP_SEPARATOR}"
      
      if File.exists?("#{backup_dir}/#{basename}#{b}#{stamp}#{ext}")
        i = 1
        while File.exists?("#{backup_dir}/#{basename}#{b}#{stamp}#{b}#{i}#{ext}")
          i += 1
        end
        stamp = "#{stamp}#{b}#{i}"
      end
      
      return create_archive("#{backup_dir}/#{basename}#{b}#{stamp}#{ext}")
    end
    
    def restore_backup(archive=parent.dir, regex = //)
      src = nil
      if File.exists?(archive) and !File.directory?(archive)
        src = archive
        if src.nil?
          raise "Argument archive: #{archive} is nil!"
        end
      else
        regex = /#{regex}/ if !regex.is_a? Regexp
        Dir.glob("#{archive}/*.zip").reverse_each do |x|
          if x.match(regex)
            src = File.realpath(x)
            break
          end
        end
        if src.nil?
          raise "#{regex.inspect} did not match anything in #{archive}"
        end
      end
      return restore_archive(src)
    end
    
    def create_archive(archive="#{dir}.zip")
      FileUtils.rm archive, :force=>true
      Zip::ZipFile.open(archive, 'w') do |zipfile|
        #Dir["#{path}/**/**"].reject{|f|f==archive}.each do |file|
        tree(:file).reject{|f|f==archive}.each do |file|
          zipfile.add(file.sub(path+'/',''),file)
        end
      end
      return archive
    end
    
    def restore_archive(archive="#{dir}.zip")
      Zip::ZipFile.open(archive) do |zip_file|
       zip_file.each do |f|
         f_path=File.join(path, f.name)
         FileUtils.mkdir_p(File.dirname(f_path))
         FileUtils.rm_r(f_path) if File.exists?(f_path)
         zip_file.extract(f, f_path) unless File.exist?(f_path)
        end
      end
      return archive
    end
    
    def inspect()
      @dir
    end
  end
  
  class FileManager
    attr_reader :file
    
    def initialize(file)
      @file = file
    end
    
    def exists?()
      File.exists?(@file)
    end
    alias :exist? :exists?
    
    def dirname()
      File.dirname(File.realpath(@file))
    end
    alias :dir :dirname
    
    def basename()
      File.basename(File.realpath(@file))
    end
    alias :base :basename
    
    def realpath()
      return @file if !exists?
      File.realpath(@file)
    end
    alias :path :realpath
    
    def dir_manager()
      DirectoryManager.new(dir)
    end
    
    def write(txt)
      FileUtils.mkdir_p(File.dirname(@file)) if !Dir.exist?(File.dirname(@file))
      #Dir.mkdir(File.dirname(@file)) if !Dir.exist?(File.dirname(@file))
      f = File.new(@file, 'w')
      f.write (txt)
      f.close
    end
    
    def append(text)
      write "#{read}#{text}"
    end
    
    def each(*args, &block)
      File.open(file) do |f|
        f.each(*args, &block)
      end
    end
    alias :each_line :each
    
    def read()
      @text = File.open(file) { |f| f.read }
    end
    
    ## Call read() before this if file has been updated
    def lines()
      @lines = []
      each { |l| @lines << "#{l}" }
      return @lines
    end
    
    ## Call read() before this if file has been updated
    def text()
      @text or read
    end
    
    def update(update_file)
      if !exists?
        write 'foo'
      end
      FileUtils.mkdir_p(dir)
      FileUtils.cp(update_file, path)
    end
    
    def md5sum()
      Digest::MD5.hexdigest(File.open(file) {|f| f.read})
    end
    
    def to_s()
      "#{path}"
    end
    
    def ==(other)
      file==other.file
    end
  end
  
  class ZippedFileManager < FileManager
    attr_reader :archive
    
    def initialize(archive, file)
      @file = file
      @archive = archive
    end
    
    def write(txt)
      Zip::ZipFile.open(@archive) do |zip_file|
        zip_file.file.open(@file, 'w') do |f|
          f.write(txt)
        end
      end
    end
    
    def read()
      Zip::ZipFile.open(@archive) do |zip_file|
        zip_file.file.open(@file) do |f|
          @text = f.read
        end
      end
      return @text
    end
    
    def each(*args, &block)
      Zip::ZipFile.open(@archive) do |zip_file|
        zip_file.file.open(@file) do |f|
          f.each(*args, &block)
        end
      end
    end
    
    def to_s()
      "#{archive}/#{file}"
    end
    
    def ==(other)
      file==other.file and archive==other.archive
    end
  end
  
  
end