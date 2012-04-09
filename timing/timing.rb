# Convert testclient output to deploytool-compatible json

puts "Copyright 2011 EfficientCloud Ltd. All Rights reserved."
puts "Usage: timing.rb timingdata.txt"

require 'rubygems'
gem 'json'
require 'json'

data = []
this_line = ""
this_time = 0
lines = File.read(ARGV.shift).split("\n")
lines.each do |line|
  next if line.match(/^<$/)
  next if line.match(/^([0-9]+) ><$/)
  m = line.match(/^([0-9]+) >(.*)/)
  if m
    if this_line != ""
      data << [this_time, 'testbuild', this_line]
      this_time = m[1].to_i
      this_line = m[2] + "\n"
    end
  else
    this_line += line + "\n"
  end
end

File.open('converted.json', 'w') do |f|
  f.puts data.to_json
end

puts "Done, open timing.html to view."

`open timing.html`
