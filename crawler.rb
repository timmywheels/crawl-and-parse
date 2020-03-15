require 'byebug'
require 'nokogiri'
require "selenium-webdriver"

USER_FLAG = true # user enters missing data (in images, js, etc)
DEBUG_FLAG = false # saves output to "debug/" dir
DEBUG_PAGE_FLAG = false # review each webpage manually

DEBUG_ST = nil  # run for a single state
OFFSET = nil
SKIP_LIST = []

# ok broken
# ri broken
# tx

class Crawler

  def parse_ak(h)
    cols = @doc.css('body')[0].text.split("\n").map {|i| i.strip}.select {|i| i.size>0}
    if (x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Confirmed cases/}.first) &&
      cols[x[1]+2] =~ /^Cumulative since 1/
      h[:positive] = string_to_i(cols[x[1]+2].split("\s").last)
    else
      @errors << 'missing positive'
    end
    if (x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Total Persons Tested for/}.first) &&
      cols[x[1]+1] =~ /^Negative samples tested at/ &&
      cols[x[1]+2] =~ /^Negative samples tested at/ &&
      cols[x[1]+3] =~ /^Cumulative since 1/
      h[:negative] = string_to_i(cols[x[1]+3].split("\s").last)
    else
      @errors << 'missing negative'
    end
    h
  end

  def parse_al(h)
    cols = @doc.css('table')[0].text.split("\n").map {|i| i.strip}.select {|i| i.size>0}
if cols[3] != 'Deaths'
    byebug unless (cols.size - 1) % 2 == 0
    byebug unless cols[1..2] == ["County of Residence", "Cases"]
    rows = (cols.size - 1)/2 - 2 # last should be Total
    h[:positive] = 0
    rows.times do |r|
      h[:positive] += string_to_i(cols[(r+1)*2+2])
    end
    byebug unless cols[(rows+1)*2+1] == 'Total'
    byebug unless h[:positive] == string_to_i(cols[(rows+1)*2+2])
    if @s.gsub(',','') =~ />Deaths:([^<]+)</
      h[:deaths] = string_to_i($1)
    else
      @errors << 'missing deaths'
    end
#begin changed 3/15/2020
else
    byebug unless (cols.size - 1) % 3 == 0
    byebug unless cols[1..3] == ["County of Residence", "Cases", "Deaths"]
    rows = (cols.size - 1)/3 - 1
    h[:positive] = 0
    h[:deaths] = 0
    rows.times do |r|
      h[:positive] += string_to_i(cols[(r+1)*3+2])
      h[:deaths] += string_to_i(cols[(r+2)*3])
    end
end
    if @s.gsub(',','') =~ /Total unique patients tested: ([0-9]+)[^0-9]/
      h[:tested] = string_to_i($1)
    else
      @errors << 'missing tested'
    end
    h
  end

  def parse_ar(h)
#@driver.navigate.to(@url) rescue nil
#byebug
    cols = @doc.css('table').map {|i| i.text}.select {|i| i=~/Confirmed Cases of COVID-19 in Arkansas/}.first.split("\n").map {|i| i.strip}.select {|i| i.size > 0}
    byebug unless cols.size == 10 # 12
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Presumed Positive Cases of COVID-19/i}.first
      h[:positive] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing positive 2'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Confirmed Cases of COVID-19 in Arkansas/i}.first
      h[:positive] = 0 unless h[:positive]
      h[:positive] += string_to_i(cols[x[1]+1])
    else
      @errors << 'missing positive'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Persons Under Investigation/i}.first
      h[:pending] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing pending'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Past PUIs with negative test/i}.first
      h[:negative] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing negative'
    end
    h
  end

  def parse_az(h)
    begin
      `rm /Users/danny/Downloads/Cases_crosstab.csv`
      `rm /Users/danny/Downloads/Testing_crosstab.csv`
      @driver.navigate.to @url
      sleep(3)
      @driver.find_elements(class: "tabCanvas")[0].click
      @driver.find_elements(class: "download")[0].click
      x = @driver.find_elements(class: "tab-downloadDialog")[0]
      x.find_elements(:css, "*")[3].click
      @driver.find_elements(class: "tabDownloadFileButton")[0].click
      byebug # manually save, required to set browser preferences
      @driver.find_elements(class: "tabCanvas")[3].click
      @driver.find_elements(class: "download")[0].click
      x = @driver.find_elements(class: "tab-downloadDialog")[0]
      x.find_elements(:css, "*")[3].click
      @driver.find_elements(class: "tabDownloadFileButton")[0].click
      sleep(2)
      `dos2unix /Users/danny/Downloads/Cases_crosstab.csv`
      `dos2unix /Users/danny/Downloads/Testing_crosstab.csv`
      rows = open('/Users/danny/Downloads/Testing_crosstab.csv').readlines.map {|i| i.strip.split("\t")}
      if i = rows.select {|i| i[0] =~ /Number of People Tested/}.first
        h[:tested] = string_to_i(i[1])
      else
        @errors << "missing tested"
      end
      if i = rows.select {|i| i[0] =~ /Number of Positive/}.first
        h[:positive] = string_to_i(i[1])
      else
        @errors << "missing positive"
      end

      if i = rows.select {|i| i[0] =~ /Number of Presumptive Positive/}.first
        h[:positive] += string_to_i(i[1])
      else
        @errors << "missing positive 2"
      end

      if i = rows.select {|i| i[0] =~ /Number of Pending/}.first
        h[:pending] = string_to_i(i[1])
      else
        @errors << "missing pending"
      end
      if i = rows.select {|i| i[0] =~ /Number of Ruled-Out/}.first
        h[:negative] = string_to_i(i[1])
      else
        @errors << "missing negative"
      end
      rows = open('/Users/danny/Downloads/Cases_crosstab.csv').readlines.map {|i| i.strip.split("\t")}
      if i = rows.select {|i| i[0] =~ /Total Cases/}.first
        byebug if string_to_i(i[1]) != h[:positive]
      else
        @errors << "missing cases"
      end
      if i = rows.select {|i| i[0] =~ /Total Deaths/}.first
        h[:deaths] = string_to_i(i[1])
      else
        @errors << "missing deaths"
      end
=begin
      if s=@driver.find_elements(class: "tab-tvTitle").map {|i| i.text}.select {|i| i=~/Data last updated \| (.+)/}.first &&
        s =~ /Data last updated \| (.+)/
        h[:date] = $1
      else
        @errors << "missing date"
      end
=end
      `mv /Users/danny/Downloads/Testing_crosstab.csv #{@path}az/#{Time.now.to_s[0..18].gsub(' ','_')}_Testing_crosstab.csv`
      `mv /Users/danny/Downloads/Cases_crosstab.csv #{@path}az/#{Time.now.to_s[0..18].gsub(' ','_')}_Cases_crosstab.csv`
    rescue => e
      @errors << "az failed: #{e.inspect}"
    end
    h
  end # parse_az

  def parse_ca(h)
    @driver.navigate.to @url
    sleep(3)
    @s = @driver.find_elements(id: 's4-workspace').first.text.gsub(/\s+/,' ')
    if @s =~ /there are a total of (.*) positive cases and (.*) deaths in California/
      h[:positive] = string_to_i($1)
      h[:deaths] = string_to_i($2)
    else
      @errors << 'CA parse failed'
    end
    # Negative from CDPH report of 778 tests on 3/7, and 88 pos => 690 neg
    h[:negative] = 690 # TODO hard coded
    h
  end

  def parse_co(h)
    s = @doc.css('body').text.gsub(',','')
    if s=~ /Positive.?: ([0-9]+)[^0-9]/
      h[:positive] = string_to_i($1)
    else
      @errors << "missing positive"
    end
    if s=~ /Indeterminate - treated as a positive: ([0-9]+)[^0-9]/
      h[:positive] += string_to_i($1)
    else
      @errors << "missing positive 2"
    end
    if s=~ /Negative.?.?: ([0-9]+)[^0-9]/
      h[:negative] = string_to_i($1)
    else
      @errors << "missing negative"
    end
    if s =~ /Total number of people tested.?.?: ([0-9]+)[^0-9]/i
      h[:tested] = string_to_i($1)
    else
      @errors << "missing tested"
    end
    if @s=~ />UPDATED: ([^<]+)</
      h[:date] = $1.strip
    else
      @errors << "missing date"
    end
    h[:pending] = 0
    if s =~ /Deaths:One female in her 80s from El Paso CountyAge:/
      h[:deaths] = 1
    else
      @errors << 'deaths changed'
    end
    h
  end

  def parse_ct(h)
    #@driver.navigate.to @url
=begin
h[:tested] = 136
h[:positive] = 11
h[:negative] = 125
h[:pending] = 0
h[:deaths] 
=end
    @s = @doc.css('body')[0].text.gsub(',','')
    if @s =~ /Total patients who tested positive \(including presumptive positive\): ([0-9]+)[^0-9]/
      h[:positive] = string_to_i($1)
    else
      @errors << 'missing positive'
    end
    h
  end

  def parse_dc(h)
    @driver.navigate.to @url
=begin
    @s = @driver.find_elements(class: 'field-items')[0].text
    if @s.gsub(',','') =~ /Update: ([^\n]+)\nNumber of patients under investigation for COVID\-19: ([0-9]+)\nNumber of negative results: ([0-9]+)\nNumber of pending results: ([0-9]+)\nNumber of presumptive positive results: ([0-9]+)\nNumber of presumptive positive results from other lab: ([0-9]+)/
      h[:date] = $1.strip
      h[:pui] = $2.to_i
      h[:negative] = $3.to_i
      h[:pending] = $4.to_i
      h[:positive] = $5.to_i
      h[:positive_other_lab] = $6.to_i
      h[:positive] += h[:positive_other_lab]
      h[:tested] = h[:negative] + h[:pending] + h[:positive]
    elsif @s.gsub(',','') =~ /Update: ([^\n]+)\nNumber of patients under investigation for COVID\-19: ([0-9]+)\nNumber of negative results: ([0-9]+)\nNumber of pending results: ([0-9]+)\nNumber of presumptive positive results: ([0-9]+)/
      h[:date] = $1.strip
      h[:pui] = $2.to_i
      h[:negative] = $3.to_i
      h[:pending] = $4.to_i
      h[:positive] = $5.to_i
      h[:tested] = h[:negative] + h[:pending] + h[:positive]
=end
    sleep(2)
begin
    @s = @driver.find_elements(id: 'page').first.text.gsub(',','').gsub(/\s+/,' ')
rescue => e
  byebug
  puts
end
    if (x = @s.scan(/Number of PHL positives: ([0-9]+)[^0-9]/)).size > 0
      h[:positive] = x.map {|i| string_to_i(i.first)}.max
    else
      @errors << "positive missing"
    end
    if (x = @s.scan(/Number of commercial lab positives: ([0-9]+)[^0-9]/)).size > 0
      h[:positive] = 0 unless h[:positive]
      h[:positive] += x.map {|i| string_to_i(i.first)}.max
    else
      @errors << "positive2 missing"
    end
    if (x = @s.scan(/Number of people tested overall: ([0-9]+)[^0-9]/)).size > 0
      h[:tested] = x.map {|i| string_to_i(i.first)}.max
    else
      @errors << "tested missing"
    end
    h
  end

  def parse_de(h)
    cols = @doc.css('table')[0].text.gsub("\r",'').split("\n").map {|i| i.strip}.select {|i| i.size>0}
    byebug unless cols.size == 10
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Positive/}.first
      h[:positive] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing positive'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Presumptive Positive/}.first
      h[:positive] = 0 unless h[:positive] 
      h[:positive] += string_to_i(cols[x[1]+1])
    else
      @errors << 'missing presumptive positive'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Negative/}.first
      h[:negative] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing negative'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Pending/}.first
      h[:pending] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing tested'
    end
    if cols[1] =~ /^\* As of ([^\.]+)\.M/
      h[:date] = $1.strip + '.M'
    else
      @errors << 'missing date'
    end
begin
    h[:tested] = h[:positive] + h[:negative] + h[:pending] 
rescue => e
  byebug
  puts
end
    h
  end

  def parse_fl(h)
    begin
      @driver.navigate.to @url
      sleep(3)
      @s = @driver.find_elements(class: "wysiwyg_content").map {|i| i.text}.select {|i| i=~/Positive Cases of COVID-19/}.first
      offset = (@s =~ /2019 Novel Coronavirus \(COVID-19\)\nas of ([^\n]+)\n Positive Cases/)
      if offset
        @s = @s[offset..-1]
        h[:date] = $1
        if @s =~ /Deaths\n([^\s]+) – Florida Residents/
          h[:deaths] = $1.to_i
        else
          @errors << "missing deaths"
        end
        h[:positive] = 0
        if @s =~ /\n([^\s]+) – Florida Residents/
          h[:positive] += $1.to_i
        end
        if @s =~ /\n([^\s]+) – Florida Resident Presumptive Positive/
          h[:positive] += $1.to_i
        end
        #if @s =~ /\n([^\s]+) – Florida Residents Diagnosed and Isolated/
        #  h[:positive] += $1.to_i
        #end
        if @s =~ /\n([^\s]+) – Florida Cases Repatriated/
          h[:positive] += $1.to_i
        end
        if @s =~ /\n([^\s]+) – Non-Florida Residents\n/
          h[:positive] += $1.to_i
        end
        if h[:positive] < 18 # as of 3/8/2020
          @errors << "missing cases"
        end
        if @s =~ /\n Number of Negative Test Results\n([^\s]+)\n/
          h[:negative] = $1.to_i
        else
          @errors << "missing negative"
        end
        if @s =~ /\n Number of Pending Test Results\n([^\s]+)\n/
          h[:pending] = $1.to_i
        else
          @errors << "missing pending"
        end
        if @s =~/\n Number of People Under Public Health Monitoring\n([^\s]+) – currently being monitored\n([^\s]+) – people monitored to date\n/
          h[:pui] = $1.to_i
          h[:pui_cumulative] = $2.to_i
        else
          @errors << "missing pui"
        end
        h[:tested] = h[:positive] + h[:negative] + h[:pending]
      else
        @errors << "fl"
      end
    rescue => e
      @errors << "fl2: #{e.inspect}"
    end
    h
  end # parse_fl

  def parse_ga(h)
    @driver.navigate.to @url
begin
    loop do
      sleep(1)
      puts "sleeping for #{@st}"
      @s = @driver.find_elements(id: 'cont1')[0].text
      break if @s.size > 10
    end
rescue => e
  byebug
  puts
end
    if @s =~ /\nTotal ([^\s]+) /
      h[:positive] = string_to_i($1)
    else
      @errors << "missing positive"
    end
    if @s =~ /\nDeaths ([^\s]+) /
      h[:deaths] = string_to_i($1) 
    else
      @errors << "missing deaths"
    end
    h
  end

  def parse_hi(h)
    if @s =~ /There have been two cases of COVID-19 identified in Hawaii/
      h[:positive] = 2
    else
      @errors << "HI updated"
    end
=begin # table removed on 3/7/2020
    rows = @doc.css('table')[0].text.gsub(" ",' ').split("\n").map {|i| i.strip}.select {|i| i.size > 0}
    if rows[0] == "Number of Confirmed Case(s)" && rows.size == 10
      h[:positive] = rows[1].to_i
      @errors << "pui" unless rows[2] == "Number of Persons Under Investigation (current, testing pending)"
      h[:pui] = rows[3].to_i
      @errors << "pui_neg" unless rows[4] == "Number of Persons Under Investigation (closed, testing negative)"
      h[:pui_cumulative] = rows[5].to_i + h[:pui] + h[:positive]
      @errors << "quarantined" unless rows[6] == "Number of Persons Under Quarantine"
      h[:quarantined] = rows[7].to_i
      @errors << "monitored" unless rows[8] == "Number of Persons Self-Monitoring with DOH supervision"
      h[:monitored] = rows[9].to_i
      h[:pui] += (h[:quarantined] + h[:monitored])
    else
      @errors << 'bad table'
    end
    if @s =~ /COVID-19 Summary of Numbers as of <\/strong><strong>([^<]+)</
      h[:date] = $1.strip
    else
      @errors << 'date'
    end
=end
    h
  end

  def parse_ia(h)
begin
    @driver.navigate.to @url
rescue => e
  byebug
  puts "fix browser"
end
    sleep(2)
    @s = @driver.find_elements(class: 'table').map {|i| i.text}.select {|i| i=~/Reported Cases in Iowa by County/}[0]
    if @s.gsub(',','') =~ /\nTotal ([0-9]+)/
      h[:positive] = string_to_i($1)
    else
      @errors << 'missing positive'
    end
=begin
    @s = @driver.find_elements(class: 'table').map {|i| i.text}.select {|i| i=~/COVID-19 Testing in Iowa/}[0]
    if @s =~ /Positive ([^\n]+)\nNegative ([^\n]+)\nPending ([^\n]+)\nTotal ([^\n]+)/
      h[:positive] = string_to_i($1)
      h[:negative] = string_to_i($2)
      h[:pending] = string_to_i($3)
      h[:tested] = string_to_i($4)
    else
      @errors << 'parse failed'
    end
=end
    # TODO parse other table
    h
  end

  def parse_id(h)
    @driver.navigate.to @url
    cols = @driver.find_elements(class: "wp-block-table")[0].text.split("\n")
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Number of people tested through the Idaho/}.first
      h[:tested] = string_to_i(x.first.split.last)
    else
      @errors << 'missing tested'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Number of people tested through commercial/}.first
      h[:tested] += string_to_i(x.first.split.last)
    else
      @errors << 'missing tested 2'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Number of lab-confirmed COVID/}.first
      h[:positive] = string_to_i(x.first.split.last)
    else
      @errors << 'missing positive'
    end
    if @driver.find_elements(id: "primary")[0].text =~ /\n* Data as of ([^\n]+)\n/
      h[:date] = $1.strip
    else
      @errors << "date"
    end
    h
  end

  def parse_il(h)
    cols = @doc.text.gsub(',','').split("\n").map {|i| i.strip}.select {|i| i.size>0}
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Positive/}.first
      h[:positive] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing positive'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Negative/}.first
      h[:negative] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing negative'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^PUIs Pending/i}.first
      h[:pending] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing pending'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Total PUI/i}.first
      h[:tested] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing tested'
    end
    if @s =~ /Information regarding the number of persons under investigation updated on ([^\.]+)\./
      h[:date] = $1.strip
    else
      @errors << "missing date"
    end
    h
  end # parse_il  

  def parse_in(h)
    @driver.navigate.to @url
    sleep(5)
    @s = @driver.find_elements(class: 'claro')[0].text
    rows = @s.split("\n")
    if @s =~ /Data as of ([^\n]+)\n/
      h[:date] = $1
    else
      @errors << 'missing date'
    end
    cols = @s.split("\n").map {|i| i.strip}.select {|i| i.size>0}
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Total Positive/}.first
      h[:positive] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing positive'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Total Deaths/}.first
      h[:deaths] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing deaths'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Total Tested/}.first
      h[:tested] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing tested'
    end
    h
  end

  def parse_ks(h)
    @driver.navigate.to @url
    puts '3rd link pdf'
    h[:tested] = 143
    h[:positive] = 8
    h[:negative] = 135
    h[:pending] = 0
    h[:deaths] = 1
    byebug
    h
  end

  def parse_ky(h)
    if @doc.text =~ /Current as of ([^\.]+)\.m. Eastern timeKentucky Coronavirus MonitoringNumber Tested: ([0-9, ]+)Positive: ([0-9, ]+)Negative: ([0-9, ]+)Note:/
      h[:date] = $1.strip
      h[:tested] = $2.to_i
      h[:positive] = $3.to_i
      h[:negative] = $4.to_i
      h[:pending] = 0
    else
      @errors << "parse failed"
    end
    h
  end

  def parse_la(h)
    @driver.navigate.to @url
    @s = @driver.find_elements(class: 'dashboard-page')[0].text 
    if @s =~ /\nData updated:([^\n]+)\n/
      h[:date] = $1.strip
    else
      @errors << 'missing date'
    end
    if @s =~ /Information\n([^\n]+)\nCases Reported\n([^\n]+)\nTests Completed\n([^\n]+)\nDeaths Reported/
      h[:tested] = string_to_i($2)
      h[:positive] = string_to_i($1)
      h[:deaths] = string_to_i($3)
    else
      @errors << 'parse failed'
    end
    h
  end

  def parse_ma(h)
    @driver.navigate.to @url
    sleep(2)
begin
    @s = @driver.find_elements(class: "ma__rich-text ").map {|i| i.text}.select {|i| i=~/onfirmed cases/}[-1]
rescue => e
  byebug
  puts
end

    if @s =~ /COVID-19 cases in Massachusetts as of ([^*]+)/
      h[:date] = $1
    else
      @errors << "missing date"
    end
    if @s =~ /\nConfirmed cases of COVID-19 ([^\n]+)\n/
      h[:positive] = $1.to_i
    else
      @errors << "missing cases"
    end
    if @s =~ /\nPresumptive positive cases of COVID-19 ([^\n]+)\n/
      h[:positive] += $1.to_i
    else
      @errors << "missing presumptive positive"
    end
    if @s =~ /\nTotal ([^\n]+)\n/
      #h[:positive] = $1.to_i
    else
      @errors << "missing tested"
    end
    # TODO parse quarantined and monitored
    h
  end # parse_ma

  def parse_md(h)
    @driver.navigate.to @url
    sleep(3)
    if @driver.find_elements(class: 'container').map {|i| i.text}.select {|i| i=~/Confirmed Cases/}[0] =~ /COVID-19 Statistics in Maryland\nNumber of Confirmed Cases: ([^\n]+)\n/
      h[:positive] = $1.to_i
    else
      @errors << "missing cases"
    end
    #h[:tested] = h[:positive] + h[:negative] + h[:pending].to_i unless h[:tested]
    h
  end

  def parse_me(h)
    cols = @doc.css('table')[0].text.split("\n").map {|i| i.strip}.select {|i| i.size > 0}
    byebug unless cols.size == 12
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Total Confirmed Cases/}.first
      h[:positive] = string_to_i(cols[x[1]+5])
    else
      @errors << 'missing positive'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Total Presumptive Positive Cases/}.first
      h[:positive] += string_to_i(cols[x[1]+5])
    else
      @errors << 'missing positive 2'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Total Preliminary Presumptive Positive Cases/}.first
      h[:positive] += string_to_i(cols[x[1]+5])
    else
      @errors << 'missing positive 3'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Persons With Tests Pending/}.first
      h[:pending] = string_to_i(cols[x[1]+5])
    else
      @errors << 'missing pending'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Persons With Negative Tests/}.first
      h[:negative] = string_to_i(cols[x[1]+5])
    else
      @errors << 'missing negative'
    end
    if x = cols.select {|i| i=~/^Updated: (.*)/}.first
      x=~/^Updated: (.*)/
      h[:date] = $1
    else
      @errors << 'missing date'
    end
    h
  end

  def parse_mi(h)
    rows = @doc.css('table')[0].text.gsub(" "," ").split("\n").map {|i| i.strip}.select {|i| i.size > 0}
    if rows[6] == "Positive for 2019-nCoV"
      if rows[0] == 'Date'
        h[:date] = rows[1]
      else
        @errors << 'missing date'
      end
      if rows[2] == "Meets PUI Criteria: Testing Approved"
        h[:pui] = rows[3].to_i
      else
        @errors << 'missing pui'
      end
      if rows[4] == "Negative for 2019-nCoV"
        h[:negative] = rows[5].to_i
      else
        @errors << 'missing neg'
      end
      if rows[6] == "Positive for 2019-nCoV"
        h[:positive] = rows[7].to_i
      else
        @errors << 'missing pos'
      end
      if rows[8] == "Test Results Pending"
        h[:pending] = rows[9].to_i
      else
        @errors << 'missing pending'
      end
      if rows[10] == "Referred for Assessment and/or Monitoring to Date**"
        h[:pui_cumulative] = rows[11].to_i
      else
        @errors << 'missing pui_cumulative'
      end
      if rows[12] == "Total Assessment and/or Monitoring Referrals Under Active Monitoring"
        h[:monitored] = rows[13].to_i
      else
        @errors << 'missing monitored'
      end
      h[:tested] = h[:negative] + h[:positive] + h[:pending]
    else
      @errors << "missing positive"
    end
    h
  end

  def parse_mn(h)
    @driver.navigate.to @url
=begin
    rows = @doc.css('table')[0].text.split("\n").map {|i| i.strip}.select {|i| i.size > 0}
    if (i = rows.find_index("Positive")) && rows[i+1] =~ /Counties/
      h[:positive] = rows[i+2].to_i
    else
      @errors << "missing positive"
    end
    if i = rows.find_index("Approximate number of patients tested")
      h[:tested] = rows[i+1].to_i
    else
      @errors << "missing tested"
    end
    if @s =~ /Patients tested<\/strong><br>\r\nAs of ([^<]+)/
      h[:date] = $1
    else
      @errors << "missing date"
    end
=end
    if @s =~ />([^>]+) approximate number of patients tested</
      h[:tested] = string_to_i($1)
    else
      @errors << "missing tested"
    end
    if @s =~ />([^>]+) positives</
      h[:positive] = string_to_i($1)
    else
      @errors << "missing positive"
    end
    h
  end  

  def parse_mo(h)
=begin
    if @s =~ />Presumptive Positive cases in Missouri: ([^<]+)</
      h[:positive] = $1.to_i
    else
      @errors << "missing cases"
    end
=end
    cols = @doc.css('table')[0].text.split("\n").map {|i| i.strip}.select {|i| i.size > 0}
    byebug unless cols.size == 8 # 10
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Negative/}.first
      h[:negative] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing negative'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Presumptive Positive/}.first
      h[:positive] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing positive 3'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^CDC Confirmed Positive/}.first
      h[:positive] = 0 unless h[:positive]
      h[:positive] += string_to_i(cols[x[1]+1])
    else
      @errors << 'missing positive 2'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Positive/}.first
      h[:positive] = 0 unless h[:positive]
      h[:positive] += string_to_i(cols[x[1]+1])
    else
      @errors << 'missing positive'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Deaths/}.first
      h[:deaths] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing deaths'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Total Patients Tested/}.first
      h[:tested] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing tested'
    end
    cols = @doc.css('table')[1].text.split("\n").map {|i| i.strip}.select {|i| i.size > 0}
    byebug unless cols.size == 2
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Positive/}.first
      h[:positive] += string_to_i(cols[x[1]+1])
    else
      @errors << 'missing positive 3'
    end
    h
  end

  def parse_ms(h)
    s = @doc.css('body').text.gsub(',','')
    if s =~ /Mississippi positive cases: ([0-9]+)[^0-9]/i
      h[:positive] = $1.to_i
    else
      @errors << "missing positive"
    end
    if s =~ /Individuals tested by the MSDH Public Health Laboratory: ([0-9]+)[^0-9]/i
      h[:tested] = string_to_i($1)
    else
      @errors << 'missing tested'
    end
    h
  end

  def parse_mt(h)
    @driver.navigate.to @url
    sleep(4)
begin
    cols = @driver.find_elements(class: 'fluid-container')[0].text.split("\n").map {|i| i.strip}.select {|i| i.size > 0}
rescue => e
  byebug
  puts
end
    byebug unless cols.size == 14
    h[:pending] = 0
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/Reported COVID\-19 Cases in Montana/}.first
      h[:positive] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing positive'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/Persons with negative results/}.first
      h[:negative] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing negative'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/Persons tested for COVID-19 by MTPHL\*/i}.first
      h[:tested] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing tested'
    end
    h
  end  

  def parse_nc(h)
    @driver.navigate.to @url
    sleep(4)
begin
    cols = @driver.find_elements(class: 'content').map {|i| i.text}.select {|i| i=~/NC Cases/i}.last.split("\n").map{|i| i.strip}.select{|i| i.size>0}
rescue => e
  byebug
  puts
end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^NC Cases/}.first
      h[:positive] = string_to_i(cols[x[1]+4])
    else
      @errors << 'missing positive'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^NC Deaths/i}.first
      h[:deaths] = string_to_i(cols[x[1]+4])
    else
      @errors << 'missing deaths'
    end
    s=@driver.find_elements(id: 'page-wrapper')[0].text 
    if s.gsub(',','') =~/\n([0-9]+) total tests completed at the NCSLPH/
      h[:tested] = string_to_i($1)
    else
      @errors << 'missing tested'
    end
    h
  end

  def parse_nd(h)
    # TODO weird js
    puts "challenging js for nd"

h[:tested] = 100
h[:positive] = 1
h[:negative] = 95
h[:pending] = 4
h[:deaths] = 0

    if USER_FLAG
      @driver.navigate.to @url
      byebug 
    end
    h
  end  

  def parse_ne(h)
    if @s =~ /<strong>.Updated&#58\; <\/strong>([^<]+)</
      h[:date] = $1
    else
      @errors << "missing date"
    end
    if @s =~ />Total number of cases – ([^<]+)</
      h[:positive] = string_to_i($1)
      h[:tested] = h[:positive]
    else
      @errors << "missing positive"
    end
    if @s =~ />Cases undergoing further testing at the Nebraska Public Health Lab - ([^<]+)</
      h[:pending] = $1.to_i
      h[:tested] += h[:pending]
    else
      @errors << 'missing pending'
    end
    if @s =~ />Cases that tested negative – ([^<]+)</
      h[:negative] = $1.to_i
      h[:tested] += h[:negative]
    else
      @errors << 'missing negative'
    end
    h
  end  

  def parse_nh(h)
#@driver.navigate.to @url
#byebug
    cols = @doc.css('table')[0].text.split("\n").map {|i| i.strip}.select {|i| i.size > 0}
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/Number of Persons with covid/i}.first
      h[:positive] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing positive'
    end
=begin
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/Number of Persons Presumptive Positive/}.first
      h[:positive] += string_to_i(cols[x[1]+1])
    else
      @errors << 'missing positive 2'
    end
=end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/Number of Persons with Test Pending/}.first
      h[:pending] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing pending'
    end
=begin
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/Number of Persons Tested \(closed, tested negative\)/}.first
      h[:negative] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing negative'
    end
=end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/Total Number of Persons Tested at NH/}.first
      h[:tested] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing tested'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/Number of Persons Being Monitored/}.first
      h[:monitored] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing monitored'
    end
=begin
    if @doc.text =~ /New Hampshire 2019 Novel Coronavirus \(COVID-19\) Summary Report \r\n\t  \(updated ([^\)]+)\)/
      h[:date] = $1
    else
      @errors << "missing date"
    end
=end
    h
  end

  def parse_nj(h)
#@driver.navigate.to @url
#byebug
    cols = @doc.css('table')[0].text.split("\n").select {|i| i.strip.size >0}
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Positive/}.first
      h[:positive] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing positive'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/PresumptivePositive/}.first
      h[:positive] += string_to_i(cols[x[1]+1])
    else
      @errors << 'missing positive 2'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/Negative/}.first
      h[:negative] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing negative'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/Persons underinvestigation/i}.first
      h[:pending] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing pending'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/Deaths/}.first
      h[:deaths] = string_to_i(cols[x[1]+1])
    else 
      @errors << 'missing deaths'
    end
    h[:tested] = h[:positive].to_i + h[:negative].to_i + h[:pending].to_i
    h
  end

  def parse_nm(h)
    @driver.navigate.to @url
    sleep(3)
begin
    cols = @driver.find_elements(class: "et_pb_text_inner").map {|i| i.text}.select {|i| i=~/COVID-19 Test Results in N/}[0].split("\n")
    @s = @driver.find_elements(class: "et_pb_text_inner").map {|i| i.text}.select {|i| i=~/COVID-19 Test Results in N/}[0]
rescue => e
  byebug
  puts
end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/Presumptive Positive/}.first
      h[:positive] = string_to_i(x[0].split.last)
    else
      @errors << 'missing positive'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/Confirmed Positive/}.first
      h[:positive] += string_to_i(x[0].split.last)
    else
      @errors << 'missing positive 2'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Negative/}.first
      h[:negative] = string_to_i(x[0].split.last)
    else
      @errors << 'missing negative'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/Total Tests/}.first
      h[:tested] = string_to_i(x[0].split.last)
    else
      @errors << 'missing tested'
    end
=begin
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/persons tested through .* and test results are from/}.first &&
        x[0] =~ /persons tested through (.*) and test results are from/
      h[:date] = $1
    else
      @errors << 'missing date'
    end
=end
    h[:pending] = 0
    h
  end

  def parse_nv(h)
    cols = @doc.css('table')[0].text.split("\n").map {|i| i.strip}.select {|i| i.size > 0}
    if cols[1] =~ /Last updated (.*)/
      h[:date] = $1
    else
      @errors << "missing date"
    end

    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Confirmed/}.first
      h[:positive] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing positive'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Presumptive/}.first
      h[:positive] += string_to_i(cols[x[1]+1])
    else
      @errors << 'missing positive 2'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Negative/}.first
      h[:negative] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing negative'
    end
    h[:pending] = 0
    h[:tested] = h[:positive] + h[:negative] rescue nil
    h
  end

  def parse_ny(h)
    begin
    if @doc.css('table')[0].text =~ /Data last updated (.+)\r/
      h[:date] = $1
    else
      @errors << "missing date"
    end
    rows = @doc.css('table')[0].text.gsub("\r","").split("\n").map {|i| i.strip}.select {|i| i.size > 0}
    if rows[-2] == "Total Positive Cases (Statewide)"
      h[:positive] = rows[-1].to_i
    else
      @errors << "missing positive"
    end
=begin
    cols = @doc.css('table')[0].css('tr')[1].text.gsub("\r",'').split("\n")
    if cols[1] != "Positive Cases" || cols.size != 5 ||
      (@doc.css('table')[0].css('tr')[0].text.gsub("\r",'').split("\n") != 
       ["", " ", "New York State(Outside of NYC)", "New York City(NYC)", "Total Positive Cases"])
      @errors << "row1"
    else
      h[:pos_outside_nyc] = cols[2].to_i
      h[:pos_nyc] = cols[3].to_i
      h[:positive] = h[:pos_outside_nyc] + h[:pos_nyc]
      h[:tested] = h[:positive]
      h[:persons_under_investigation] = cols[4].to_i
    end
    if @doc.css('table')[0].css('tr')[2]
      cols = @doc.css('table')[0].css('tr')[2].text.gsub("\r",'').split("\n")
      if cols[1] != "Negative Results\t"
        @errors << "row2"
      else
        h[:neg_outside_nyc] = cols[2].to_i
        h[:neg_nyc] = cols[3].to_i
        h[:tested] += h[:neg_outside_nyc] + h[:neg_nyc]
      end
    else
      @errors << "missing neg, removed on 3/7/2020"
      h[:tested] = nil
    end
    if @doc.css('table')[0].css('tr')[3] 
      cols = @doc.css('table')[0].css('tr')[3].text.gsub("\r",'').split("\n")
      if cols[1] != "Pending Test Results\t"
        @errors << "row2"
      else
        h[:pending_outside_nyc] = cols[2].to_i
        h[:pending_nyc] = cols[3].to_i
        h[:tested] += h[:pending_outside_nyc] + h[:pending_nyc] if h[:tested]
      end
    else
      @errors << "missing pending, removed on 3/7/2020"
      h[:tested] = nil
    end
=end
    rescue => e
      @errors << "rescue ny: #{e.inspect}"
    end
    h
  end

  def parse_oh(h)
    @driver.navigate.to @url
    sleep(3)
begin
    cols = @driver.find_elements(class: 'odh-ads__container')[0].text.split("\n").map {|i| i.strip}.select {|i| i.size > 0}
rescue => e
  byebug
  puts
end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Confirmed Cases/}.first
      h[:positive] = string_to_i(cols[x[1]-1])
    else
      @errors << 'missing positive'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Negative PUI/}.first
      h[:negative] = string_to_i(cols[x[1]-1])
    else
      @errors << 'missing negative'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Persons Under Investigation/}.first
      h[:pending] = string_to_i(cols[x[1]-1])
    else
      @errors << 'missing pending'
    end
    h[:tested] = h[:positive] + h[:pending] + h[:negative]
=begin
    if @s =~ /<em>Last Updated: ([^\s]+) <\/em><\/strong><\/span>/
      h[:date] = $1
    else
      @errors << "missing date"
    end
=end
    h
  end

  def parse_ok(h)
#@driver.navigate.to(@url) rescue nil
#byebug
    cols = @doc.css('table').map {|i| i.text}.select {|i| i=~/Oklahoma Test Results/}.last.split("\n").select {|i| i.strip.size > 0}
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/Positive \(Confirmed\)/}.first
      h[:positive] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing positive'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/Positive \(Presumptive\*\)/}.first
      h[:positive] += string_to_i(cols[x[1]+1])
    else
      @errors << 'missing positive 2'
    end
    if @s =~ />\^ Out of state residents\.</

    else
      # table changed, might need to include another row
      byebug
      puts
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Negative/}.first
      h[:negative] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing negative'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/PUIs Pending Results/}.first
      h[:pending] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing pending'
    end
    h[:tested] = h[:positive].to_i + h[:negative].to_i + h[:pending].to_i
=begin removed 3/12/2020
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/Total Tested/}.first
      h[:tested] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing tested'
    end
=end
    h
  end  

  def parse_or(h)
    begin
      x = @doc.css('table')[0].css('tr')[0].text.gsub("\r",'')
      if x =~ /As of (.*)/
        h[:date] = $1
      end
      x = @doc.css('table')[0].css('tr')[1].text.gsub("\r",'').split("\n")
      byebug unless x[0] == "Positive"
      h[:positive] = string_to_i(x[1])
      x = @doc.css('table')[0].css('tr')[2].text.gsub("\r",'').split("\n")
      byebug unless x[0] =~ /^Negative/
      h[:negative] = string_to_i(x[1])
      x = @doc.css('table')[0].css('tr')[3].text.gsub("\r",'').split("\n")
      byebug unless x[0] == "Pending"
      h[:pending] = string_to_i(x[1])
      x = @doc.css('table')[0].css('tr')[4].text.gsub("\r",'').split("\n")
      h[:tested] = string_to_i(x[1])
      x = @doc.css('table')[1].css('tr')[0].text.gsub("\r",'')
      if x =~ /Last updated (.*)/
        h[:pum_date] = $1
      end
      x = @doc.css('table')[1].css('tr')[1].text.gsub("\r",'').split("\n")
      byebug unless x[0] == "Currently under monitoring"
      h[:pum_current] = x[1].to_i
      x = @doc.css('table')[1].css('tr')[2].text.gsub("\r",'').split("\n")
      byebug unless x[0] == "PUM who have"
      h[:pum_complete] = x[-1].to_i
      x = @doc.css('table')[1].css('tr')[3].text.gsub("\r",'').split("\n")
      byebug unless x[0] =~ /^Total PUM/
      h[:pum_total] = x[1].to_i
      h[:pui] = h[:pum_current]
      h[:pui_cumulative] = h[:pum_total]
    rescue => e
      @errors << "failed to parse: #{e.inspect}"
    end
    h
  end  

  def parse_pa(h)
    @driver.navigate.to @url
    sleep(3)
begin
    cols = @driver.find_elements(class: "ms-rteTable-default").map {|i| i.text}.select {|i| i=~/Persons Under/}.first.split("\n")
rescue => e
  byebug
  puts
end
    if @s =~ />PA COVID-19 Update – ([^<]+)</
      h[:date] = $1.strip
    else
      @errors << "missing date"
    end
    if cols[1] == "Negative Pending Positive"
      x = cols[2..-1].map {|i| i.split}.flatten.map {|i| i.strip}.select {|i| i.size>0}.map {|i| string_to_i(i)}
      h[:pui] = x[0]
      h[:negative] = x[1]
      h[:pending] = x[2]
      h[:positive] = x[3]
      #h[:positive] += x[4].to_i
      h[:tested] = h[:positive] + h[:negative] + h[:pending]
    else
      @errors << "parse error"
    end
    h
  end

  def parse_ri(h)
    @driver.navigate.to @url
    sleep(6)
begin
    @s = @driver.find_elements(class: 'panel')[0].text
rescue => e
  puts e.inspect
  byebug
end
=begin
    if @s =~ /Last Update: ([^\n]+)\n/
      h[:date] = $1
    else
      @errors << 'missing date'
    end
=end
    rows = @s.split("\n").map{|i| i.strip}.select{|i| i.size>0}
    t = rows.select {|i| i=~ /Number of Rhode Island COVID-19 positive \(including presumptive positive\) cases:/}
    if t.size == 1 
      h[:positive] = string_to_i(t[0].split("\s").last)
    else
      @errors << 'positive'
    end
    t = rows.select {|i| i=~ /Number of people who had negative test results at RIDOH/}
    if t.size == 1 
      h[:negative] = string_to_i(t[0].split("\s").last)
    else
      @errors << 'negative'
    end
    t = rows.select {|i| i=~ /Number of people for whom tests are pending/}
    if t.size == 1 
      h[:pending] = string_to_i(t[0].split("\s").last)
    else
      @errors << 'pending'
    end
    t = rows.select {|i| i=~ /Approximate number of people who are currently instructed to self-quarantine in Rhode Island/}
    if t.size == 1 
      h[:quarantined] = string_to_i(t[0].split("\s").last)
    else
      @errors << 'quarantined'
    end
begin
    h[:tested] = h[:positive] + h[:negative] + h[:pending]
rescue => e
byebug
puts
end
    h
  end

  def parse_sc(h)
#@driver.navigate.to @url
#byebug
    # todo date on page
    rows=@doc.css('table')[0].text.split("\n").map {|i| i.strip}.select {|i| i.size > 0}
    if i = rows.find_index("Negative tests")
      h[:negative] = string_to_i(rows[i+1])
    else
      @errors << "missing negative"
    end
    if i = rows.find_index("Presumptive positives")
      h[:positive] = string_to_i(rows[i+1])
    else
      @errors << "missing pres positive"
    end
    if i = rows.find_index("Positive tests")
      h[:positive] = 0 unless h[:positive]
      h[:positive] += string_to_i(rows[i+1])
    else
      @errors << "missing positive"
    end
    h[:pending] = 0
    h[:tested] = h[:positive] + h[:negative]
    h
  end

  def parse_sd(h)
begin
    rows = @doc.css('table')[0].text.split("\n").map {|i| i.strip}.select {|i| i.size > 0}
    if rows[0] == "Positive*"
      h[:positive] = rows[1].to_i
      h[:tested] = h[:positive]
    else
      @errors << "missing cases"
    end
    if rows[2] == "Negative"
      h[:negative] = rows[3].to_i
      h[:tested] += h[:negative]
    else
      @errors << "missing negative"
    end
    if rows[4] == "Pending"
      h[:pending] = rows[5].to_i
      h[:tested] += h[:pending]
    else
      @errors << "missing pending"
    end
    if @s =~ /<h2><strong>As of ([^<]+)<\/strong>/
      h[:date] = $1.strip
    else
      @errors << "missing date"
    end
rescue => e
  puts 'parse failed'
  byebug
  puts
end
    h
  end  

  def parse_tn(h)
#@driver.navigate.to @url
#byebug
    cols = @doc.css('table')[0].text.split("\n").map {|i| i.strip}.select {|i| i.size > 0}
    if cols.size != 14
      byebug
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/Total positives in TN/}.first
      h[:positive] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing positive'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/State Public Health Laboratory/}.first
      h[:tested] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing tested'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/All other commercial and private laboratori/}.first
      h[:tested] += string_to_i(cols[x[1]+2]) + string_to_i(cols[x[1]+3])
    else
      @errors << 'missing tested 2'
    end
    h[:pending] = 0
    h
  end

  def parse_tx(h)
begin
    rows = @doc.css('table')[0].text.split("\n").map {|i| i.strip}
    if ind = rows.find_index('Total')
      h[:positive] = rows[ind+2].to_i
    else
      @errors << "tx"
    end
rescue => e
  byebug
  puts
end
    h
  end # parse_tx  

  def parse_ut(h)
    @driver.navigate.to @url
    sleep(3)
begin
    @s = @driver.find_elements(id: 'x-root')[0].text
rescue => e
  byebug
  puts
end
    if @s =~ /Number of confirmed Utah residents with COVID-19\n([^\n]+)\n/
      h[:positive] = string_to_i($1)
    else
      @errors << 'missing positive'
    end
    h
  end # parse_ut

  def parse_va(h)
    puts "tableu for va"
    @driver.navigate.to @url
h[:tested] = 408
h[:positive] = 45
h[:negative]
h[:pending]
h[:deaths]

    byebug
    h
  end  

  def parse_vt(h)
    if @s =~ /Last updated: ([^<]+)</
      h[:date] = $1.strip
    else
      @errors << "missing date"
    end
    rows = @doc.css('table')[0].text.split("\n").map {|i| i.strip}.select {|i| i.size > 0}
    if i = rows.find_index("Vermonters being monitored")
      h[:pui] = rows[i+1].to_i
    else
      @errors << "missing monitored"
    end
    if i = rows.find_index("Vermonters who have completed monitoring")
      h[:pui_cumulative] = rows[i+1].to_i + h[:pui]
    else
      @errors << "missing pui cumulative"
    end
    if i = rows.find_index("Vermonters tested negative for COVID-19")
      h[:negative] = rows[i+1].to_i
    else
      @errors << "missing negative"
    end
    if i = rows.find_index("Vermont cases of COVID-19")
      h[:positive] = rows[i+1].to_i
    else
      @errors << "missing positive"
    end
    h[:pending] = 0
    h[:tested] = h[:negative] + h[:positive]
    h
  end

  def parse_wa(h)
    @driver.navigate.to @url
    sleep(3)
begin
  cols = @driver.find_elements(class: 'contentmain')[0].text.split("\n").map {|i| i.strip}.select {|i| i.size > 0}
rescue => e
  byebug
  puts
end

    x = cols.select {|i| i=~/^Positive\s+([^\s+]+)/}
    if x.size == 1 && x[0] =~ /^Positive\s+([^\s+]+)/
      h[:positive] = string_to_i($1)
    else
      @errors << 'positive'
    end
    x = cols.select {|i| i=~/^Negative\s+([^\s+]+)/}
    if x.size == 1 && x[0] =~ /^Negative\s+([^\s+]+)/
      h[:negative] = string_to_i($1)
    else
      @errors << 'negative'
    end
    if (x=cols.select {|i| i=~/^Total / && i.split.size==3}).size > 0 
      h[:deaths] = string_to_i(x[0].split.last)
    else
      @errors << 'missing deaths'
    end
=begin
    if (x=cols.select {|i| i=~/updated on/i}.first) && x =~ /updated on(.+)/
      h[:date] = $1.strip
    else
      @errors << "missing date"
    end
    # 3/7/2020 this was removed
    if i = (@s =~ /Number of people under public health supervision/)
      if @s[i..(i+1000)].split("\n")[1] =~ /<td>(.+)<\/td>/
        h[:public_health_supervision] = $1
      else
        @errors << "missing 1"
      end
    else
      @errors << "missing monitoring, removed on 3/7/2020"
    end
=end
    h[:pending] = 0
    h[:tested] = h[:negative] + h[:positive] rescue nil
    h
  end

  def parse_wi(h)
    if @s =~ /As of ([^<]+)</
      h[:date] = $1.strip
    else
      @errors << "missing date"
    end
    rows = @doc.css('table')[0].text.split("\n").map {|i| i.strip}.select {|i| i.size>0}
    if i = rows.find_index("Positive")
      h[:positive] = string_to_i(rows[i+1])
      h[:tested] = h[:positive]
    else
      @errors << "missing cases"
    end
    if i = rows.find_index("Negative")
      h[:negative] = string_to_i(rows[i+1])
      h[:tested] += h[:negative]
    else
      @errors << "missing negative"
    end
    if i = rows.find_index("Pending")
      h[:pending] = string_to_i(rows[i+1])
      h[:tested] += h[:pending]
    else
      @errors << "missing pending"
    end
    if i = rows.find_index("Positive: Recovered")
      h[:recovered] = string_to_i(rows[i+1])
      h[:tested] += h[:recovered]
      h[:positive] += h[:recovered]
    else
      @errors << "missing recovered"
    end
    h
  end # parse_wi

  def parse_wv(h)
    @driver.navigate.to @url
    sleep(3)
begin
    cols = @driver.find_elements(class: 'bluebkg')[0].text.split("\n").map {|i| i.strip}.select {|i| i.size > 0}
rescue => e
  byebug
  puts
end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/Total Positive Cases/}.first
      h[:positive] = string_to_i(cols[x[1]-1])
    else
      @errors << 'missing positive'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/Total Negative Cases/}.first
      h[:negative] = string_to_i(cols[x[1]-1])
    else
      @errors << 'missing negative'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/Total Deaths/}.first
      h[:deaths] = string_to_i(cols[x[1]-1])
    else
      @errors << 'missing deaths'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/Tests Pending/}.first
      h[:pending] = string_to_i(cols[x[1]-1])
    else
      @errors << 'missing pending'
    end
    h[:tested] = h[:negative] + h[:positive] + h[:pending] rescue nil
    if (x=cols.select {|i| i=~/Updated:/i}.first) && x =~ /updated:(.+)/i
      h[:date] = $1.strip
    else
      @errors << "missing date"
    end
    h
  end

  def parse_wy(h)
    if @s =~ /At this time there are ([^\s]+) reported Wyoming cases\./
      h[:positive] = string_to_i($1)
    else
      @errors << "cases found"
    end
    h
  end

  ######################################

  # TODO birth is hard coded
  def search_term(word='death')

#return nil

      if (i = (@doc.text =~ /#{word}/i)) && !(@doc.text =~ /birth/i)
        puts "found #{word} in #{@st}"
        puts @doc.text[(i-30)..(i+30)]
        return true
      end
      @driver.navigate.to @url
      if (i = (@driver.page_source =~ /#{word}/i)) && !(@doc.text =~ /birth/i)
        puts "found #{word} in #{@st}"
        puts @driver.page_source[(i-30)..(i+30)]
        return true
      end
      false
  end

  def string_to_i(s)
    return s if s.class == Integer
    return 0 if s == "--"
    if s =~ /Appx\. (.*)/
      s = $1
    elsif s =~ /~(.*)/
      s = $1
    elsif s =~ /App/
      byebug
      ''
    end
    case s.strip
    when "zero"
      0
    when "one"
      1
    when "two"
      2
    when "three"
      3
    when "four"
      4
    when "five"
      5
    when "six"
      6
    when "seven"
      7
    when "eight"
      8
    when "nine"
      9
    when "ten"
      10
    else
      if s =~ /in progress/
        nil
      else
        s = s.strip.gsub('‡','').gsub(',','')
        if s =~ /([0-9]+)/
          $1.to_i
        else
          puts "invalid number string"
          byebug
          nil
        end
      end
    end
  end

  def initialize
    @driver = Selenium::WebDriver.for :firefox
    @path = if DEBUG_FLAG
      'debug/data/'
    else
      'data/'
    end
    @path_csv = if DEBUG_FLAG
      'debug/data_csv/'
    else
      'data_csv/'
    end
    # load previous numbers
    lines = open('all.csv').readlines.map {|i| i.split("\t")}
    @h_prev = {}
    lines.each do |st, tested, positive, deaths, junk|
      st.downcase!
      @h_prev[st] = {}
      @h_prev[st][:tested] = tested.to_i if tested.size > 0
      @h_prev[st][:positive] = positive.to_i if positive.size > 0
      @h_prev[st][:deaths] = deaths.to_i if deaths.size > 0
    end
  end

  def method_missing(m, h)
    puts "skipping state: #{@st}"
    #puts "Error: all states should be covered now" # KS missing
    #byebug
    if USER_FLAG
      @driver.navigate.to @url
      byebug 
    end
    h
  end

  def run
    h_all = []
    errors_crawl = []
    tested   = {:all => 0}
    positive = {:all => 0}
    deaths   = {:all => 0}
    pui      = {:all => 0}
    #pui_cumulative
    #quarantined

    skip_flag = OFFSET

    for @st, @url in (open('states.csv').readlines.map {|i| i.strip.split("\t")}.map {|st, url| [st.downcase, url]})
      puts "CRAWLING: #{@st}"

      skip_flag = false if @st == OFFSET
      next if skip_flag

      next if SKIP_LIST.include?(@st)

      next unless @st == DEBUG_ST if DEBUG_ST
      `mkdir -p #{@path}#{@st}`
      @s = `curl -s #{@url}`
      @doc = Nokogiri::HTML(@s)
      @errors = []
      h = {:ts => Time.now, :st => @st, :source => @url}
      h = send("parse_#{@st}", h)
      open("#{@path}#{@st}/#{Time.now.to_s[0..18].gsub(' ','_')}", 'w') {|f| f.puts @s} # @s might be modified in parse

      count = 0
      tested_new = 0
      count += 1 if h[:tested]
      if h[:positive]
        count += 1
        tested_new += h[:positive]
      end
      if h[:negative]
        count += 1
        tested_new += h[:negative]
      end
      if h[:pending]
        count += 1
        tested_new += h[:pending]
      end
      # do this in the second parse_log.rb step
      # h[:tested] = tested_new unless h[:tested]

      if @h_prev[@st][:tested] == h[:tested] && @h_prev[@st][:positive] == h[:positive] && @h_prev[@st][:deaths] == h[:deaths]
        # no change
      elsif @h_prev[@st][:tested] == h[:tested] && @h_prev[@st][:positive] == h[:positive]
        puts "only deaths different, old h"
        puts @h_prev[@st]
        puts "new h:"
        puts h.inspect
        @driver.navigate.to(@url) rescue nil
        byebug
        puts
      elsif @h_prev[@st][:positive] == h[:positive]
        if h[:tested] 
          puts "tested different, old h"
          puts @h_prev[@st]
          puts "new h:"
          puts h.inspect
          @driver.navigate.to(@url) rescue nil
          byebug
          puts
        else
          # missing tested in new
        end
      elsif !h[:positive]
        puts "missing positive"
        puts h.inspect
        @driver.navigate.to(@url) rescue nil
        byebug
        puts
      elsif h[:positive] < @h_prev[@st][:positive]
        puts "positive decreased"
        puts h.inspect
        @driver.navigate.to(@url) rescue nil
        byebug
        puts 
      elsif ((h[:tested] && tested_new > h[:tested]) || count == 3 || (count == 4 && (h[:tested] != (h[:positive] + h[:negative] + h[:pending])))) && !h[:skip]
        puts "please double check stats, old h is:"
        puts @h_prev[@st]
        puts "new h is:"
        puts h.inspect
        @driver.navigate.to(@url) rescue nil
        byebug
        puts
      end

      positive[:all] += h[:positive].to_i
      positive[@st.to_sym] = h[:positive]

      deaths[:all] += h[:deaths].to_i
      deaths[@st.to_sym] = h[:deaths]

      pui[:all] += h[:pui].to_i
      pui[@st.to_sym] = h[:pui]

      tested[:all] += h[:tested].to_i
      tested[@st.to_sym] = h[:tested]

      h[:error] = @errors

      if @errors.size != 0 && !h[:skip]
        puts "error in #{@st}! #{@errors.inspect}"
        puts h.inspect
        errors_crawl << @st
        @driver.navigate.to @url
        byebug
        puts
      end

      if DEBUG_PAGE_FLAG
        @driver.navigate.to @url
        puts
        puts @st
        puts h.inspect
        puts
        puts({:tested => h[:tested], :pos => h[:positive], :neg => h[:negative], :pending => h[:pending]}.inspect)
        byebug
        puts
      end

      unless h[:deaths]
        if search_term('death')
          puts h.inspect
          byebug
          puts
        end
      end

      h_all << h  
      # save parsed h
      open("#{@path}#{@st}.log",'a') {|f| f.puts h.inspect} if h && h.size > 0 && !(h[:skip])
    end

    puts
    puts "positive:"
    puts positive.inspect
    puts
    puts "deaths:"
    puts deaths.inspect
    puts
    puts "pui:"
    puts pui.inspect
    puts
    puts "tested:"
    puts tested.inspect
    puts
    puts "errors:"
    puts errors_crawl.inspect
    
    `mkdir -p #{@path_csv}`
    open("#{@path_csv}stats_#{Time.now.to_s[0..15].gsub(' ','_').gsub(':','-')}.csv",'w') do |f|
      f.puts ['state', 'tested', 'cases', 'deaths'].join("\t")
      f.puts tested.to_a.map {|st, v| [st.to_s, v, positive[st], deaths[st]].join("\t")}.sort
    end

    # TODO save each data type in separate csv

    byebug
    puts "done."

  end # end run

end # end Crawler class

Crawler.new.run
