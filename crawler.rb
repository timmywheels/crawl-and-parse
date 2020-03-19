require 'byebug'
require 'nokogiri'
require "selenium-webdriver"

USER_FLAG = true # user enters missing data (in images, js, etc)
DEBUG_FLAG = false # saves output to "debug/" dir
DEBUG_PAGE_FLAG = false # review each webpage manually

DEBUG_ST = nil  # run for a single state
OFFSET = nil
SKIP_LIST = []

# TODO
# ma need to parse pdf
# md broken
# ms broken
# nd todo
# or get deaths
# sd get deaths
# ut broken, has deaths and tested
# va
# ri should work, but page is slow

class Crawler

  def parse_ak(h)
    @driver.navigate.to @url
    cols = @driver.find_elements(class:'box')[1].text.gsub(',','').split("\n").map {|i| i.strip}.select {|i| i.size>0}
    if (x = cols.select {|i| i=~ /Cumulative since 1\/1\/2020: /}).size == 2
      if x[0] =~ /Cumulative since 1\/1\/2020: ([0-9]+)/
        h[:positive] = string_to_i($1)
      else
        @errors << 'missing positive'
      end
      if x[1] =~ /Cumulative since 1\/1\/2020: ([0-9]+)/
        h[:negative] = string_to_i($1)
      else
        @errors << 'missing negative'
      end
    else
      @errors << 'parse error'
    end
    byebug if h[:positive] > h[:negative]
    h[:tested] = h[:positive] + h[:negative]
    h
  end

  def parse_al(h)
    cols = @doc.css('table')[0].text.split("\n").map {|i| i.strip}.select {|i| i.size>0}
if cols[3] != 'Deaths'
    byebug unless (cols.size - 0) % 2 == 0
    byebug unless cols[2..3] == ["County of Residence", "Cases"]
    rows = (cols.size - 2)/2 - 2 # last should be Total
    h[:positive] = 0
    rows.times do |r|
      h[:positive] += string_to_i(cols[(r+2)*2+1])
    end
    byebug unless cols[(rows+1)*2+2] == 'Total'
    byebug unless h[:positive] == string_to_i(cols[(rows+1)*2+3])
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
    if @s.gsub(',','') =~ /Total unique / #patients tested: ([0-9]+)[^0-9]/
byebug # was missing before
      h[:tested] = string_to_i($1)
    else
      # @errors << 'missing tested'
    end
    h
  end

  def parse_ar(h)
#@driver.navigate.to(@url) rescue nil
#byebug
    cols = @doc.css('table').map {|i| i.text}.select {|i| i=~/Confirmed Cases of COVID-19 in Arkansas/}.first.split("\n").map {|i| i.strip}.select {|i| i.size > 0}
    byebug unless cols.size == 7 # 10 # 12
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
    cols = @doc.css('table').map {|i| i.text}.select {|i| i=~/Persons Under Investigation/}.first.split("\n").map {|i| i.strip}.select {|i| i.size > 0}
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Persons Under Investigation/i}.first
      h[:pending] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing pending'
    end
    cols = @doc.css('table').map {|i| i.text}.select {|i| i=~/Past PUIs with negative test/}.first.split("\n").map {|i| i.strip}.select {|i| i.size > 0}
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Past PUIs with negative test/i}.first
      h[:negative] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing negative'
    end
    h
  end

  def parse_az(h)
#@driver.navigate.to(@url) rescue nil
#byebug
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
      @driver.find_elements(class: "tabCanvas")[9].click
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
        #byebug if string_to_i(i[1]) != h[:positive]
        h[:positive] = string_to_i(i[1])
      else
        @errors << "missing total cases"
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
#@driver.navigate.to @url
#byebug
    s = @doc.css('body').text.gsub(',','')
    if s =~ /\n([0-9]+) cases\n([0-9]+) hospitalized\n([0-9]+) counties\n([0-9]+) people tested\n([0-9]+) deaths/
      h[:positive] = string_to_i($1)
      h[:tested] = string_to_i($4)
      h[:deaths] = string_to_i($5)
    else
      @errors << "parse failed"
    end
    h
  end

  def parse_ct(h)
#@driver.navigate.to @url
# byebug
    cols = @doc.css('table')[0].text.gsub(',','').split("\n").map {|i| i.strip}.select {|i| i.size>0}
    if cols[3] == "Positive Cases" && cols[-2] == 'Total'
      h[:positive] = string_to_i(cols[-1])
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
    @s = @s.encode('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: '')
    if @s =~ /https:\/\/dshs.maps.arcgis.com([^"]+)"/
      @driver.navigate.to('https://dshs.maps.arcgis.com' + $1)
    else
      @errors << 'dashboard url not found'
      return h
    end
    @s = @driver.find_elements(class: 'layout-reference')[0].text
    if @s =~ /Positive Cases\n([^\n]+)\nTotal Deaths\n([^\n]+)\n/
      h[:positive] = string_to_i($1)
      h[:deaths] = string_to_i($2)
    else
      @errors << 'parse failed'
    end
    # TODO counties
    h
  end

  def parse_fl(h)
    @driver.navigate.to @url
    cols = @driver.find_elements(class: "situation__boxes-wrapper")[0].text.gsub(',','').split("\n").map {|i| i.strip}.select {|i| i.size>0}
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Total Cases Overview/}.first
      h[:positive] = string_to_i(cols[x[1]-1])
    else
      @errors << 'missing positive'
    end
    s = @driver.find_elements(class: "inner--box").map {|i| i.text}.select {|i| i=~/\nDeaths/}.last
    if s =~ /\nDeaths ([^\n]+)/
      h[:deaths] = string_to_i($1)
    else
      @errors << 'missing deaths'
    end
# https://fdoh.maps.arcgis.com/apps/opsdashboard/index.html#/8d0de33f260d444c852a615dc7837c86
# @driver.find_elements(class: 'button--orange').first.click
    if @driver.page_source =~ /"([^"]+)arcgis\.com([^"]+)"/
      url = $1 + 'arcgis.com' + $2
      @driver.navigate.to url
      sec = 15
      loop do
        if @driver.page_source =~ /https:\/\/arcg.is([^"]+)"/
          @driver.navigate.to(url = 'https://arcg.is' + $1)
          @driver.find_elements(class: 'tab-title')[1].click
          s = @driver.find_elements(class: 'dashboard-page')[0].text
          if s =~ /\nTotal Tests\n([^\n]+)\n/
            h[:tested] = string_to_i($1)
          else
            @errors << 'missing tested'
          end
          break
        else
          sec -= 1
          puts 'sleeping'
          sleep 1
          if sec == 0
            @errors << '2nd dash link not found'
            break
          end
        end
      end
    else
      @errors << 'dashboard not found'
    end
    h
  end # parse_fl

  def parse_ga(h)
    @driver.navigate.to @url
    cols = @driver.find_elements(class:'stacked-row-plus').map {|i| i.text.gsub(',','')}.select {|i| i=~/Confirmed cases and deaths in Georgia/}[0].split("\n")
    if (x = cols.select {|v,i| v=~/^Total ([0-9]+) /}.first) && x=~/^Total ([0-9]+) /
      h[:positive] = string_to_i($1)
    else
      @errors << 'missing positive'
    end
    if (x = cols.select {|v,i| v=~/^Deaths ([0-9]+) /}.first) && x=~/^Deaths ([0-9]+) /
      h[:deaths] = string_to_i($1)
    else
      @errors << 'missing deaths'
    end
    cols = @driver.find_elements(class:'stacked-row-plus').map {|i| i.text.gsub(',','')}.select {|i| i=~/COVID-19 Testing by Lab/}[0].split("\n")
    if cols.size == 4
      h[:tested] = string_to_i(cols[2].split.last) + string_to_i(cols[3].split.last)
    else
      @errors << 'missing tested'
    end
    # TODO counties
    cols = @driver.find_elements(class:'stacked-row-plus').map {|i| i.text.gsub(',','')}.select {|i| i=~/COVID-19 Confirmed Cases by County/}[0].split("\n")
    h
  end

  def parse_hi(h)
# TODO table in image
#@driver.navigate.to @url
#byebug
    if @s =~ /There have been ([^s]+) cases of COVID-19 identified in Hawaii/
      h[:positive] = string_to_i($1)
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
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Total number of lab-confirmed COVID-19/}.first
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
    @driver.navigate.to @url
    cols = @driver.find_elements(class: "flex-container")[0].text.gsub(',','').split("\n").map {|i| i.strip}.select {|i| i.size>0}
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
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Deaths/}.first
      h[:deaths] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing deaths'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^PUIs Pending/i}.first
      h[:pending] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing pending'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Total Tested/i}.first
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
    puts 'pdf might have more data'
    @driver.navigate.to @url
    sec = 15
    loop do
      @s = @driver.page_source
      if @s.gsub(',','') =~ /([0-9]+) Confirmed Positive Test Res/
        h[:positive] = string_to_i($1)
        break
      end
      sec -= 1
      puts 'sleeping'
      sleep 1
      if sec == 0
        @errors << 'missing positive'
        break
      end
    end
    h
  end

  def parse_ky(h)
    @driver.navigate.to @url
    puts "death manual"
    byebug
    cols = @driver.find_elements(class: 'alert-success')[0].text.gsub(',','').split("\n").map {|i| i.strip}.select {|i| i.size >0}
    if (x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Number Tested:/}.first) && x[0] =~ /^Number Tested: ([0-9]+)/
      h[:tested] = string_to_i($1)
    else
      @errors << 'missing tested'
    end
    if (x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Positive:/}.first) && x[0] =~ /^Positive: ([0-9]+)/
      h[:positive] = string_to_i($1)
    else
      @errors << 'missing positive'
    end
    h
  end

  def parse_la(h)
    @driver.navigate.to @url
    if @s =~ /src="https:\/\/www.arcgis.com([^"]+)/
      @driver.navigate.to('https://www.arcgis.com' + $1)
    else
      @errors << 'link failed'
      return h
    end
    @s = @driver.find_elements(class: 'layout-reference')[0].text
    if @s =~ /\nData updated:([^\n]+)\n/
      h[:date] = $1.strip
    else
      @errors << 'missing date'
    end
    if @s =~ /Information\n([^\n]+)\nCases Reported\*?\n([^\n]+)\nDeaths Reported\nTests Completed by State Lab\n([^\n]+)\n/
      h[:tested] = string_to_i($3)
      h[:positive] = string_to_i($1)
      h[:deaths] = string_to_i($2)
    else
      @errors << 'parse failed'
    end
    h
  end

  def parse_ma(h)
h[:tested] = 1743 + 306 + 222
h[:positive] = 256
h[:negative]
h[:pending]
h[:deaths] 
puts 'in pdf'
    @driver.navigate.to @url
byebug
    h
  end # parse_ma

  def parse_md(h)
    # TODO county, age
    @driver.navigate.to @url
    sec = 10
    while sec > 0 && !(@driver.find_elements(class: 'container').map {|i| i.text}.select {|i| i=~/Confirmed Cases/}[0] =~ /COVID-19 Statistics in Maryland\nNumber of Confirmed Cases: ([^\n]+)\n/)
      puts 'sleeping...'
      sleep(1)
      sec -= 1
    end
    if sec > 0
      h[:positive] = $1.to_i
    else
      @errors << "missing cases"
    end
    h
  end

  def parse_me(h)
#@driver.navigate.to @url
#byebug
    cols = @doc.css('table').map {|i| i.text}.select {|i| i=~/Confirmed Cases/}.first.split("\n").map {|i| i.strip}.select {|i| i.size > 0}
    byebug unless cols.size == 8
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Confirmed Cases/}.first
      h[:positive] = string_to_i(cols[x[1]+3])
    else
      @errors << 'missing positive'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Presumptive Positive Cases/}.first
      h[:positive] = 0 unless h[:positive]
      h[:positive] += string_to_i(cols[x[1]+3])
    else
      @errors << 'missing positive 2'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Negative Tests/}.first
      h[:negative] = string_to_i(cols[x[1]+3])
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
    # TODO county, sex, age, hospitalization
    @driver.navigate.to @url
    @driver.find_elements(class: 'readLink').select {|i| i.text =~ /GO TO CUMULATIVE DATA/i}[0].click
    cols = @driver.find_elements(class: 'fullContent')[0].text.gsub(',','').split("\n").map {|i| i.strip}.select {|i| i.size>0}
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Total$/}.first
      h[:positive] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing positive'
    end
    h
  end

  def parse_mn(h)
    @driver.navigate.to @url
    sec = 15
    cols = []
    loop do
      begin
        cols = @driver.find_elements(id: 'body')[0].text.gsub(',','').split("\n").map {|i| i.strip}.select {|i| i.size > 0}
        byebug unless cols.size == 13
        break
      rescue => e
        puts 'sleeping'
        sleep 1
        sec -= 1
        break if sec == 0
      end
    end
    if x = cols.select {|v,i| v=~/Approximate number of patients tested /}.first
      h[:tested] = string_to_i(x.split.last)
    else
      @errors << 'missing tested'
    end
    if (x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Positive:/}.first) &&
      x[0] =~ /^Positive: ([0-9]+)/
      h[:positive] = string_to_i($1)
    else
      @errors << 'missing positive'
    end
    h
  end  

  def parse_mo(h)
    tables = tables = @doc.css('table').map {|i| i.text.gsub(',','')}
    cols = tables.select {|i| i=~/Total Patients Tested/}[0].split("\n").map {|i| i.strip}.select {|i| i.size > 0}
    byebug unless cols.size == 8
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
    if (tables.size == 3) && (cols = tables.last.split("\n").map {|i| i.strip}.select {|i| i.size > 0}) && (cols[0]=='Positive')
      h[:positive] += string_to_i(cols[1])
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
  cols = @driver.find_elements(class: 'fluid-container')[0].text.split("\n").map {|i| i.strip}.select {|i| i.size > 0}
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
    sec = 15
    cols = []
    loop do
      begin
        cols = @driver.find_elements(class: 'content').map {|i| i.text}.select {|i| i=~/NC Cases/i}.last.split("\n").map{|i| i.strip}.select{|i| i.size>0}
        byebug unless cols.size == 13
        break
      rescue => e
        sleep 1
        puts 'sleeping'
        sec -= 1
        break if sec == 0
      end
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^NC Cases/}.first
      h[:positive] = string_to_i(cols[x[1]+5])
    else
      @errors << 'missing positive'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^NC Deaths/i}.first
      h[:deaths] = string_to_i(cols[x[1]+5])
    else
      @errors << 'missing deaths'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^NC Completed Tests/i}.first
      h[:tested] = string_to_i(cols[x[1]+5])
    else
      @errors << 'missing tested'
    end
    h
  end

  def parse_nd(h)
    # TODO weird js
    puts "challenging js for nd"

h[:tested] = 362
h[:positive] = 7
h[:negative] = 355
h[:pending] = 0
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
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Positive/}.first
      h[:positive] = string_to_i(x[0].split.last)
    else
      @errors << 'missing positive'
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
#@driver.navigate.to @url
#byebug
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
    @driver.navigate.to @url
    puts "death manual"
    h[:deaths] = nil
    byebug
    rows = @doc.css('table')[0].text.gsub(',','').split("\n").map {|i| i.strip}.select {|i| i.size>0}
    if rows[-2] == "Total Number of Positive Cases"
      h[:positive] = rows[-1].to_i
    else
      @errors << "missing positive"
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
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Cumulative Number of Individuals\*\* Under Health Supervision/}.first
      h[:pui_cumulative] = string_to_i(cols[x[1]-1])
    else
      @errors << 'missing pending'
    end
    #h[:tested] = h[:positive] + h[:pending] + h[:negative]
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
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/Positive \(In-State\)/}.first
      h[:positive] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing positive'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/Positive \(Out-of-State\)/}.first
      h[:positive] = 0 unless h[:positive]
      h[:positive] += string_to_i(cols[x[1]+1])
    else
      @errors << 'missing positive'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/Positive \(Presumptive\*\)/}.first
      h[:positive] += string_to_i(cols[x[1]+1])
    else
      @errors << 'missing positive 2'
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
    @driver.navigate.to @url
    cols = @driver.find_elements(class: 'card-body').map {|i| i.text.gsub(',','')}.select {|i| i=~/Oregon Test Results as of /}.first.split("\n")
    if (x = cols.select {|v,i| v=~/^Positive ([0-9]+)/}.first) && x=~/^Positive ([0-9]+)/
      h[:positive] = string_to_i($1)
    else
      @errors << 'missing positive'
    end
    if (x = cols.select {|v,i| v=~/^Negative ([0-9]+)/}.first) && x=~/^Negative ([0-9]+)/
      h[:negative] = string_to_i($1)
    else
      @errors << 'missing negative'
    end
    if (x = cols.select {|v,i| v=~/^Pending ([0-9]+)/}.first) && x=~/^Pending ([0-9]+)/
      h[:pending] = string_to_i($1)
    else
      @errors << 'missing pending'
    end
    if (x = cols.select {|v,i| v=~/^Total /}.first) 
      h[:tested] = string_to_i(x.split.last)
    else
      @errors << 'missing tested'
    end
    h
  end  

  def parse_pa(h)
    @driver.navigate.to @url
    s = @driver.find_elements(class: 'ms-rteTable-default')[0].text.gsub(',','')
    if s =~ /Negative Positive\n([0-9]+) ([0-9]+)/
      h[:negative] = string_to_i($1)
      h[:positive] = string_to_i($2)
    else
      @errors << 'missing pos neg'
    end
    h[:deaths] = 0
    h[:county_positive] = []
    cols = @driver.find_elements(class: 'ms-rteTable-default')[1].text.gsub(',','').split("\n").map {|i| i.strip}
    if cols.shift == "County Cases" && cols.shift == 'Deaths'
      for col in cols
        if col =~ /([^\s]+) ([0-9]+) ([0-9]+)/
          h[:deaths] += string_to_i($3)
          h[:county_positive] << [$1, string_to_i($2)]
        elsif col =~ /^([^\s]+) ([0-9]+)$/
          h[:county_positive] << [$1, string_to_i($2)]
        elsif col =~ /^([^\s]+)$/
          h[:county_positive] << [$1]
        elsif col =~ /^([0-9]+)$/
          h[:county_positive].last << string_to_i($1)
        else
          @errors << 'county parse failed'
        end
      end
    else
      @errors << "missing deaths"
    end
    h
  end

  def parse_ri(h)
    @driver.navigate.to @url
    sec = 15
    loop do
      begin
        (@s = @driver.find_elements(class: 'panel')[0].text.gsub(',','')) =~ /Number of Rhode Island COVID-19/
        raise unless s
        break
      rescue
        sleep(1)
        sec -= 1
        break if sec == 0
      end
    end
    cols = @s.split("\n")
    if (x = cols.select {|v,i| v=~/^Number of Rhode Island COVID-19 positive \(including/}.first)
      h[:positive] = string_to_i(x.strip.split.last)
    else
      @errors << 'missing pos'
    end
    if (x = cols.select {|v,i| v=~/^Number of people who had negative test results at RIDOH/}.first)
      h[:negative] = string_to_i(x.strip.split.last)
    else
      @errors << 'missing neg'
    end
    if (x = cols.select {|v,i| v=~/^Number of people for whom tests are pending/}.first)
      h[:pending] = string_to_i(x.strip.split.last)
    else
      @errors << 'missing pending'
    end
    h[:tested] = h[:positive].to_i + h[:negative].to_i + h[:pending].to_i
    h
  end

  def parse_sc(h)
    @driver.navigate.to @url
    sec = 15
    rows = []
    loop do
      begin
        rows = @driver.find_elements(id: 'dmtable')[0].text.gsub(',','').split("\n").map {|i| i.strip}.select {|i| i.size > 0}
        raise if rows.size == 0
        break
      rescue => e
        sec -= 1
        break if sec == 0
        puts 'sleeping'
        sleep(1)
      end
    end
    if rows.select {|i| i=~/Negative tests /}[0].gsub(',','') =~ /Negative tests \(Public Health Laboratory only\) ([0-9]+)/
      h[:negative] = string_to_i($1)
    else
      @errors << "missing negative"
    end
    if rows.select {|i| i=~/Positive tests/}[0].gsub(',','') =~ /Positive tests ([0-9]+)/
      h[:positive] = string_to_i($1)
    else
      @errors << "missing positive"
    end
    h[:pending] = 0
    h[:tested] = h[:positive].to_i + h[:negative].to_i
    if @driver.page_source =~ /iframe src="([^"]+)"/
      iframe = $1
      @driver.navigate.to iframe
      if x=@driver.find_elements(class: 'dock-element').map {|i| i.text.gsub(',','')}.select {|i| i=~/Deaths in Individuals with COVID-19 infection/}.first
        h[:deaths] = string_to_i(x.split("\n").last)
      else
        @errors << 'missing deaths'
      end
    else
      @errors << 'missing iframe'
    end
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
    @driver.navigate.to @url
rescue => e
  byebug
  puts
end
# check browser
byebug
    rows = @doc.css('table')[0].text.gsub(',','').split("\n").map {|i| i.strip}.select {|i| i.size>0}
    if rows[0] == 'Total' && rows[2] == 'Public Labs'
      h[:tested] = string_to_i(rows[1])
    else
      @errors << 'missing tested'
    end
    rows = @doc.css('table')[1].text.gsub(',','').split("\n").map {|i| i.strip}.select {|i| i.size>0}
    if rows[2] == "Deaths"
      h[:deaths] = string_to_i(rows[3])
    else
      @errors << 'missing deaths'
    end
    if rows[0] == "Total Statewide Cases"
      h[:positive] = string_to_i(rows[1])
    else
      @errors << 'missing positive'
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
    if @s =~ /Utah residents with confirmed COVID-19\n([^\n]+)\n/
      h[:positive] = string_to_i($1)
    else
      @errors << 'missing positive'
    end
    if @s =~ /Visitors with confirmed COVID-19\n([^\n]+)\n/
      h[:positive] = 0 unless h[:positive] 
      h[:positive] += string_to_i($1)
    else
      @errors << 'missing positive 2'
    end
    if @s =~ /\nLast updated ([^\n]+)\n/
      h[:date] = $1
    else
      @errors << 'date missing'
    end
    h
  end # parse_ut

  def parse_va(h)
    puts "tableu for va"
    @driver.navigate.to @url
h[:tested] = 1278
h[:positive] = 77
h[:negative]
h[:pending]
h[:deaths]

    byebug
    h
  end  

  def parse_vt(h)
#@driver.navigate.to @url
#byebug
    if @s =~ /Last updated: ([^<]+)</
      h[:date] = $1.strip
    else
      @errors << "missing date"
    end
    cols = @doc.css('table')[0].text.split("\n").map {|i| i.strip}.select {|i| i.size > 0}
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/Positive test results/}.first
      h[:positive] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing positive'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/People being monitored/}.first
      h[:monitored] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing monitored'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/People who have completed monitoring/}.first
      h[:monitored_cumulative] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing monitored cum'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/Total tests/}.first
      h[:tested] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing tested'
    end
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
    @driver.navigate.to @url
    if @s =~ /As of ([^<]+)</
      h[:date] = $1.strip
    else
      @errors << "missing date"
    end
    @s = @driver.find_elements(id: 'main')[0].text.gsub(',','')
    if @s =~ /\nNegative ([0-9]+)\nPositive ([0-9]+)\n/
      h[:positive] = string_to_i($2)
      h[:negative] = string_to_i($1)
    else
      @errors << "missing cases"
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
#@driver.navigate.to @url
#byebug
    if @s =~ /At this time there are ([^\s]+) reported Wyoming cases\./
      h[:positive] = string_to_i($1)
    else
      @errors << "cases found"
    end
    h[:tested] = 0
    if @s =~ /Tests completed at Wyoming Public Health Laboratory: ([^<]+)</
      h[:tested] += string_to_i($1)
    else
      @errors << "missing tested"
    end
    if @s =~ /Tests completed at CDC lab: ([^<]+)</
      h[:tested] += string_to_i($1)
    else
      @errors << "missing tested 2"
    end
    if @s =~ /Test results reported by commercial labs: ([^<]+)</
      h[:tested] += string_to_i($1)
    else
      @errors << "missing tested 3"
    end
    if @s =~ /Confirmed cases: ([^<]+)</
      byebug unless h[:positive] == string_to_i($1)
    else
      @errors << "missing confirmed 2"
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
    when 'eleven'
      11
    else
      if s =~ /in progress/
        nil
      else
        s = s.strip.gsub('‡','').gsub(',','')
        if s =~ /([0-9]+)/
          $1.to_i
        else
          puts "invalid number string: #{s}"
          temp = nil
          byebug
          return temp
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
