
require 'pdf/reader'
require 'byebug'

arr = []
PDF::Reader.open('test.pdf') do |reader|
  reader.pages.each do |page|
byebug
    arr << page.text
  end
end

byebug

puts
