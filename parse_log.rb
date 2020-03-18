require 'byebug'

h_state = {}
open('states.csv').readlines.map {|i| i.strip.split("\t")}.each {|st, url| h_state[st.upcase] = url}

arr = []
for file in `ls data/*.log`.split("\n")

  h_latest = {}
  # sorted by date
  for line in open(file).readlines
    line.strip!
    if line =~ /:ts=>([^,}]+)/
      date = $1
    else
      byebug
      puts
    end
    h = eval(line.gsub(date,'"' + date + '"'))

    tested = h[:tested]
    positive = h[:positive] || h[:cases]
    deaths = h[:deaths]
    negative = h[:negative].to_i
    ts = h[:ts]
    date = h[:date]
    source = h[:source] || h_state[h[:st].upcase]
    raise unless source

    h_latest[:negative] = negative unless h_latest[:negative]
    if negative >= h_latest[:negative]
      h_latest[:negative] = negative 
    elsif negative > 0
      puts "neg smaller! #{h[:st]} #{negative} #{h_latest[:negative]}"
      h_latest[:negative] = negative
    end

    if tested
      if h_latest[:tested] && h_latest[:tested].to_i > tested.to_i
        puts line
        puts h_latest
        puts tested
        #byebug
        puts 
      else
        h_latest[:tested] = tested
      end
      h_latest[:tested_date] = date || ts
      h_latest[:tested_source] = source
    end
    if positive
      if h_latest[:positive] && h_latest[:positive].to_i > positive.to_i
        #byebug
      else
        h_latest[:positive] = positive
      end
      h_latest[:positive_date] = date || ts
      h_latest[:positive_source] = source
    end

    _tested = h_latest[:positive].to_i + h_latest[:negative].to_i + h_latest[:pending].to_i
    if _tested > h_latest[:tested].to_i
      puts "update tested #{h[:st]} #{_tested} #{h_latest[:tested]}"
      h_latest[:tested] = _tested
    end

    if deaths 
      if h_latest[:deaths] && h_latest[:deaths].to_i > deaths.to_i
        byebug
        puts
      else
        h_latest[:deaths] = deaths
      end
      h_latest[:deaths_date] = date || ts
      h_latest[:deaths_source] = source
    end

  end # line

  if h_latest[:tested].to_i < h_latest[:positive].to_i
    h_latest[:tested] = h_latest[:positive].to_i
  end

  # pending only uses last one
  new_tested = h_latest[:positive].to_i + h_latest[:negative].to_i + h[:pending].to_i
  if new_tested > h_latest[:tested].to_i
    puts line
    puts new_tested
    puts h_latest
    #byebug
    h_latest[:tested] = new_tested
  end

  arr << [h[:st].upcase, h_latest[:tested], h_latest[:positive], h_latest[:deaths], h_latest[:tested_date], h_latest[:positive_date], h_latest[:deaths_date], h_latest[:tested_source], h_latest[:positive_source], h_latest[:deaths_source]].join("\t")
end

diff_count = 0
j = 0
# open prev all.csv and compare
lines = open('all.csv').readlines
lines.shift
lines.map {|i| i.split("\t")}.each do |st, tested, positive, deaths, junk| 
  st2, tested2, positive2, deaths2, junk = arr[j].split("\t")
  byebug unless st2.downcase == st.downcase
  byebug if tested.to_i > tested2.to_i
  byebug if positive.to_i > positive2.to_i
  byebug if deaths.to_i > deaths2.to_i
  if tested.to_i != tested2.to_i || positive.to_i != positive2.to_i || deaths.to_i != deaths2.to_i
    diff_count += 1
    puts "#{diff_count}\t#{st2} changed from: [#{[tested, positive, deaths].join(" , ")}] to [#{[tested2, positive2, deaths2].join(" , ")}]"
  end
  j += 1
end
puts "#{diff_count} states updated."

open('all.csv','w') do |fout|
  fout.puts ['state', 'tested', 'positive', 'deaths', 'tested crawl date', 'positive crawl date', 'deaths crawl date', 'tested source', 'positive source', 'deaths source'].join("\t")
  fout.puts arr
end

x=arr.map {|i| i.split("\t")}
puts [x.map {|i| i[1].to_i}.sum, x.map {|i| i[2].to_i}.sum, x.map {|i| i[3].to_i}.sum].join("\t")

`scp all.csv ubuntu@coronavirusapi.com:policydock/`

