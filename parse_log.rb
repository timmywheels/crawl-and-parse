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
      raise
      byebug
      puts
    end
    h = eval(line.gsub(date,'"' + date + '"'))

    tested = h[:tested]
    positive = h[:positive] || h[:cases]
    deaths = h[:deaths]
    ts = h[:ts]
    date = h[:date]
    source = h[:source] || h_state[h[:st].upcase]
    raise unless source

    if tested
      if h_latest[:tested] && h_latest[:tested].to_i > tested.to_i
        byebug
      else
        h_latest[:tested] = tested
      end
      h_latest[:tested_date] = date || ts
      h_latest[:tested_source] = source
    end
    if positive
      if h_latest[:positive] && h_latest[:positive].to_i > positive.to_i
        byebug
      else
        h_latest[:positive] = positive
      end
      h_latest[:positive_date] = date || ts
      h_latest[:positive_source] = source
    end
    if deaths 
      if h_latest[:deaths] && h_latest[:deaths].to_i > deaths.to_i
        byebug
      else
        h_latest[:deaths] = deaths
      end
      h_latest[:deaths_date] = date || ts
      h_latest[:deaths_source] = source
    end
  end # line
  arr << [h[:st].upcase, h_latest[:tested], h_latest[:positive], h_latest[:deaths], h_latest[:tested_date], h_latest[:positive_date], h_latest[:deaths_date], h_latest[:tested_source], h_latest[:positive_source], h_latest[:deaths_source]].join("\t")
end
puts ['state', 'tested', 'positive', 'deaths', 'tested crawl date', 'positive crawl date', 'deaths crawl date', 'tested source', 'positive source', 'deaths source'].join("\t")
puts arr
