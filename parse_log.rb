require 'byebug'

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
    source = h[:source]

    if tested
      h_latest[:tested] = tested
      h_latest[:tested_date] = date || ts
    end
    if positive
      h_latest[:positive] = positive
      h_latest[:positive_date] = date || ts
    end
    if deaths
      h_latest[:deaths] = deaths
      h_latest[:deaths_date] = date || ts
    end
  end # line
  arr << [h[:st].upcase, h_latest[:tested], h_latest[:positive], h_latest[:deaths], h_latest[:tested_date], h_latest[:positive_date], h_latest[:deaths_date]].join("\t")
end
puts ['state', 'tested', 'positive', 'deaths', 'tested date', 'positive date', 'deaths date'].join("\t")
puts arr
