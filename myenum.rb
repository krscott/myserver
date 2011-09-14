module Enumerable
  def to_fixed_columns()
    width = []
    each do |row|
      row.each_with_index do |x, i|
        width << 0 while width[i].nil?
        width[i] = x.size if x.size > width[i] and row.size > 1
      end
    end
    out = ''
    each do |row|
      row.each_with_index do |x, i|
        out << "#{x.ljust(width[i])} "
      end
      out << "\n"
    end
    return out
  end
  
  def to_tabbed_columns()
    map { |r| r.join("\t") }.join("\n")
  end
end

class String
  def to_fixed_columns()
    gsub("\r",'').split("\n").map{|x| x.split("\t")}.to_fixed_columns
  end
end