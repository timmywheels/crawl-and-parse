require 'byebug'
require 'nokogiri'
require "selenium-webdriver"

USER_FLAG = false # user enters missing data (in images, js, etc)
DEBUG_FLAG = true # saves output to "debug/" dir
DEBUG_PAGE_FLAG = false # review each webpage manually

DEBUG_ST = nil  # run for a single state
OFFSET = nil

class Crawler

  def parse_al(h)
    if @s =~ /At this time, no COVID-19 cases have been identified in Alabama/
      h[:positive] = 0
    else
      @errors << "cases found"
    end
    if @s =~ / ([0-9,]+) tests have been run since ADPH began testing on March 5/
      h[:tested] = string_to_i($1)
    else
      @errors << "no tests"
    end
    h
  end

  def parse_ak(h)
    if @s =~ /Updated ([^;]+); updates made daily by 12:30pm<\/em><\/p><\/div>\r\n<h4>Confirmed cases<\/h4>\r\n<ul><li><strong>Current: ([^<]+)<\/strong><\/li>\r\n<li>Cumulative since 1\/1\/2020: ([^<]+)</
      h[:date] = $1
      h[:current_positive] = $2.to_i
      h[:positive] = $3.to_i 
    else
      @errors << "missing cases"
    end
    if @s =~ /Persons Under Investigation \(PUI\)\*<\/a><\/h4>\r\n<ul><li><strong>Current: ([^\s]+) \(pending tests\)<\/strong><\/li>\r\n<li>Cumulative since 1\/1\/2020: ([^\s]+) /
      h[:pui] = $1.to_i
      h[:pending] = h[:pui]
      h[:tested] = $2.to_i
      h[:pui_cumulative] = h[:tested]
      h[:negative] = h[:tested] - h[:positive] - h[:pending] # TODO PUI might not mean all tested
    else
      @errors << "missing pui"
    end
    h
  end

  def parse_ar(h)
    rows = @doc.css('table')[0].text.split("\n").map {|i| i.strip}.select {|i| i.size > 0}
    byebug unless rows.size == 12
    if i = rows.find_index("Confirmed Cases of COVID-19 in Arkansas")
      h[:positive] = rows[i+1].to_i
    else
      @errors << "missing positive"
    end
    if i = rows.find_index("Presumed Positive Cases of COVID-19 in Arkansas")
      h[:positive] += rows[i+1].to_i
    else
      @errors << "missing positive 2"
    end
    if i = rows.find_index("Persons Under Investigation (PUI)")
      h[:pui] = rows[i+1].to_i
      h[:pending] = 0 # not clear if pui is tested
    else
      @errors << "missing pui"
    end
    if i = rows.find_index("Recent travelers being monitored with daily ADH check-in and guidance")
      h[:monitored] = rows[i+1].to_i
    else
      @errors << "missing monitored"
    end
    if i = rows.find_index("Past PUIs with negative test results")
      h[:negative] = rows[i+1].to_i
      h[:tested] = h[:negative] + h[:positive]
    else
      @errors << "missing negative"
    end
    h
  end

  def parse_az(h)
    begin
      `rm /Users/danny/Downloads/Total_and_deaths_crosstab.csv`
      `rm /Users/danny/Downloads/Testing_crosstab.csv`
      @driver.navigate.to @url
      sleep(5)
      @driver.find_elements(class: "tabCanvas")[4].click
      @driver.find_elements(class: "download")[0].click
      x = @driver.find_elements(class: "tab-downloadDialog")[0]
      x.find_elements(:css, "*")[3].click
      @driver.find_elements(class: "tabDownloadFileButton")[0].click
      byebug # manually save, required to set browser preferences
      @driver.find_elements(class: "tabCanvas")[7].click
      @driver.find_elements(class: "download")[0].click
      x = @driver.find_elements(class: "tab-downloadDialog")[0]
      x.find_elements(:css, "*")[3].click
      @driver.find_elements(class: "tabDownloadFileButton")[0].click
      sleep(2)
      `dos2unix /Users/danny/Downloads/Total_and_deaths_crosstab.csv`
      `dos2unix /Users/danny/Downloads/Testing_crosstab.csv`
      rows = open('/Users/danny/Downloads/Testing_crosstab.csv').readlines.map {|i| i.strip.split("\t")}
      if i = rows.select {|i| i[0] =~ /Number of People Tested/}.first
        h[:tested] = string_to_i(i[1])
      else
        @errors << "missing tested"
      end
      if i = rows.select {|i| i[0] =~ /Number of Confirmed Positive/}.first
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
      rows = open('/Users/danny/Downloads/Total_and_deaths_crosstab.csv').readlines.map {|i| i.strip.split("\t")}
      if i = rows.select {|i| i[0] =~ /Total Cases/}.first
        byebug if string_to_i(i[3]) != h[:positive]
      else
        @errors << "missing cases"
      end
      if i = rows.select {|i| i[0] =~ /Total Deaths/}.first
        h[:deaths] = string_to_i(i[3])
      else
        @errors << "missing deaths"
      end
      if @driver.find_elements(class: "tab-tvTitle")[0].text.strip =~ /Data last updated \| (.+)/
        h[:date] = $1
      else
        @errors << "missing date"
      end
      `mv /Users/danny/Downloads/Testing_crosstab.csv #{@path}az/#{Time.now.to_s[0..18].gsub(' ','_')}_Testing_crosstab.csv`
      `mv /Users/danny/Downloads/Total_and_deaths_crosstab.csv #{@path}az/#{Time.now.to_s[0..18].gsub(' ','_')}_Total_and_deaths_crosstab.csv`
    rescue => e
      @errors << "az failed: #{e.inspect}"
    end
    h
  end # parse_az

  def parse_ca(h)
    @s.gsub!("&#160;",'')
=begin
    if @s =~ /As of(.+), there are a total of(.+)positivecases and(.+)death in California:(.+)cases are from repatriation flights. The other(.+)confirmed cases include(.+)that are travel related,(.+)due to person-to-person,(.+)community acquired and(.+)from unknown sources/
      h[:date] = $1.strip
      h[:positive] = string_to_i($2)
      h[:deaths] = string_to_i($3)
      h[:case_repatriation] = string_to_i($4)
      h[:case_other] = string_to_i($5)
      h[:case_other_travel] = string_to_i($6)
      h[:case_other_p2p] = string_to_i($7)
      h[:case_other_community] = string_to_i($8)
      h[:case_unknown] = string_to_i($9)
=end
    if @s =~ /As(.+)Pacific Time, there are a total of(.+)positive cases and(.+)deathsin California/
      h[:date] = $1.strip
      h[:positive] = string_to_i($2)
      h[:deaths] = string_to_i($3)
    else # regex doesn't match
      @errors << "CA not parsed"
      h[:s] = @s
    end
    # Negative from CDPH report of 778 tests on 3/7, and 88 pos => 690 neg
    h[:negative] = 690
    puts "review manually"
    @driver.navigate.to @url
    byebug
    h
  end

  def parse_co(h)
# old page
=begin
    if @doc.text.gsub(',','') =~ /Colorado COVID19 cases as of (.+)m:\s+([0-9]+)All cases are presumptive positive/
      h[:date] = $1 + 'm'
      h[:positive] = $2.to_i
    else
      @errors << "missing cases"
    end
    # this was removed on 3/7/2020 by Colorado
    if @doc.css('table')[0] && (rows = @doc.css('table')[0].text.split("\n").map {|i| i.strip}.select {|i| i.size > 0}) && rows[0] == "Positive"
      # date?
      h[:positive] = rows[1].to_i
      h[:negative] = rows[3]
      h[:pui] = rows[5].to_i
      h[:tested] = rows[7].to_i
    else
      @errors << "missing tested table, removed on 3/7/2020"
    end
=end
=begin removed 3/9/2020
    if @s =~ />UPDATED: <\/span><span class=\"[^"]*\">([^<]+)</
      h[:date] = $1.strip
    else
      @errors << "missing date"
    end
    if @doc.css('table')[0].text.gsub(',','') =~ /Positive([0-9]+)Negative([0-9]+)Total tests\*([0-9]+)/
      h[:positive] = $1.to_i
      h[:negative] = $2.to_i
      h[:tested] = $3.to_i
      h[:pending] = 0
    else
      @errors << "missing tests"
    end
=end
    if @s=~ />Positive:([^<]+)</
      h[:positive] = string_to_i($1)
    else
      @errors << "missing positive"
    end
    if @s=~ />Indeterminate treated as a positive:([^<]+)</
      h[:positive] += string_to_i($1)
    else
      @errors << "missing positive 2"
    end
    if @s=~ />Negative:([^<]+)</
      h[:negative] = string_to_i($1)
    else
      @errors << "missing negative"
    end
    if @s=~ />Total Tests\*:([^<]+)</
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
    h
  end

  def parse_ct(h)
    if @s =~ /Data updates from the Connecticut Department of Public Health State Laboratory as of ([^<]+)</
      h[:date] = $1.strip
    else
      @errors << "missing date"
    end
    rows = @doc.css('table')[0].text.split("\n").map {|i| i.strip}.select {|i| i.size > 0}
    begin
      h[:positive] = rows.select {|i| i=~ /Total patients who tested positive/}[0].split("\s").last.gsub(',','').to_i
      h[:negative] = rows.select {|i| i=~ /Total patients who tested negative/}[0].split("\s").last.gsub(',','').to_i
      if rows.select {|i| i=~ /ending/}.size > 0
        @errors << 'missing pending'
      end
      h[:pending] = 0
      h[:tested] = h[:positive] + h[:negative] + h[:pending]
    rescue => e
      @errors << e.inspect
    end
    h
  end

  def parse_dc(h)
    @driver.navigate.to @url
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
    else
      @errors << "parse failed"
    end
    h
  end

  def parse_de(h)
    rows = @doc.css('table')[0].text.gsub("\r",'').split("\n").map {|i| i.strip}.select {|i| i.size>0}
    if rows[1] =~ /^\* As of ([^\.]+)\.M/
      h[:date] = $1.strip + '.M'
    else
      @errors << 'missing date'
    end
    if rows[2] == 'Positive'
      h[:positive] = rows[3].to_i
    else
      @errors << 'missing positive'
    end
    if rows[4] == 'Negative'
      h[:negative] = rows[5].to_i
    else
      @errors << 'missing negative'
    end
    if rows[6] == 'Pending'
      h[:pending] = rows[7].to_i
    else
      @errors << 'missing pending'
    end
    h[:tested] = h[:positive] + h[:negative] + h[:pending]
    rows = @doc.css('table')[1].text.gsub("\r",'').split("\n").map {|i| i.strip}.select {|i| i.size>0}
    if rows[1] =~ /^\* As of ([^\.]+)/
      h[:date_pui] = $1.strip
    else
      @errors << 'missing date pui'
    end
    if rows[2] == "People currently being monitored"
      h[:pui] = rows[3].to_i
    else
      @errors << 'missing pui'
    end
    if rows[4] =~ /Total monitored/
      h[:pui_cumulative] = rows[5].to_i
    else
      @errors << 'missing pui_cumulative'
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
        if @s =~ /\n([^\s]+) – Florida Cases Repatriated/
          h[:positive] += $1.to_i
        end
        if @s =~ /\n([^\s]+) – Non-Florida resident/
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
    if @s =~ /Currently, there are ([^\s]+) confirmed and ([^\s]+) presumptive positive cases of COVID-19 in Georgia\./
      h[:positive] = string_to_i($1) + string_to_i($2)
    else
      @errors << "missing cases"
    end
    h
  end

  def parse_hi(h)
    if @s =~ /Update: On March 8th, the second presumptive positive case of COVID-19 was identified in Hawaii/
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
    puts "captcha"
    byebug # for captcha
    @s = @driver.find_elements(class: 'table').map {|i| i.text}.select {|i| i=~/COVID-19 Testing in Iowa/}[0]
    if @s =~ /Positive ([^\n]+)\nNegative ([^\n]+)\nPending ([^\n]+)\nTotal ([^\n]+)/
      h[:positive] = string_to_i($1)
      h[:negative] = string_to_i($2)
      h[:pending] = string_to_i($3)
      h[:tested] = string_to_i($4)
    else
      @errors << 'parse failed'
    end
    # TODO parse other table
    h
  end

  def parse_id(h)
    @driver.navigate.to @url
    rows = @driver.find_elements(class: "wp-block-table")[0].text.split("\n")
    if rows[3] =~ /^Number of confirmed/
      h[:positive] = rows[3].split("\s").last.to_i
      @errors << "monitored" unless rows[0] =~ /Total number of people monitored by Idaho public health \(past \& present/
      h[:monitored_done] = rows[0].split("\s").last.to_i
      @errors << "pui_cumulative" unless rows[1] =~ /Number of people no longer being monitored by public health/
      h[:pui_cumulative] = rows[1].split("\s").last.to_i
      @errors << "tested" unless rows[2] =~ /Number of people tested through the Idaho Bureau of Laboratories/
      h[:tested] = rows[2].split("\s").last.to_i
    else
      @errors << "missing confirmed"
    end
    if @driver.find_elements(id: "primary")[0].text =~ /\n* Data as of ([^\n]+)\n/
      h[:date] = $1.strip
    else
      @errors << "date"
    end
    h
  end

  def parse_il(h)
    rows = @doc.css('table').map {|i| i.text}.select {|i| i=~/Coronavirus Disease 2019 \(COVID-19\) in Illinois Test Results/}[0].split("\n").select {|i| i.size > 0}
    if i = rows.find_index("Positive (confirmed)")
      h[:positive] = rows[i+1].to_i
    else
      @errors << "missing positive"
    end
    if i = rows.find_index("Negative")
      h[:negative] = rows[i+1].to_i
    else
      @errors << "missing negative"
    end
    if i = rows.find_index("PUIs Pending")
      h[:pending] = rows[i+1].to_i
    else
      @errors << "missing pending"
    end
    if i = rows.find_index("Total PUI")
      h[:tested] = rows[i+1].to_i
    else
      @errors << "missing tested"
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
    if @s =~ /Total Positive Cases\n([^\n]+)\nTotal Deaths\n([^\n]+)\nTotal Tested by ISDH\n([^\n]+)\n/
      h[:positive] = string_to_i($1)
      h[:deaths] = string_to_i($2)
      h[:tested] = string_to_i($3)
    else
      @errors << 'missing tested'
    end 
    h
  end

  def parse_ks(h)
    @driver.navigate.to @url
    puts '3rd link pdf'
    h[:tested]
    h[:positive] = 1
    h[:negative] = 25
    h[:pending] = 13
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
    if @s =~ /There are ([^\s]+) presumptive positive cases of COVID-19/
      h[:positive] = string_to_i($1)
    else
      @errors << "missing cases"
    end
    h
  end

  def parse_ma(h)
    @driver.navigate.to @url
    sleep(1)
    s = @driver.find_elements(class: "ma__rich-text ").map {|i| i.text}.select {|i| i=~/confirmed cases/}[-1]

    if s =~ /COVID-19 cases in Massachusetts as of ([^*]+)/
      h[:date] = $1
    else
      @errors << "missing date"
    end
    if s =~ /\nTotal confirmed cases of COVID-19 ([^\n]+)\n/
      h[:positive] = $1.to_i
    else
      @errors << "missing cases"
    end
    if s =~ /\nTotal presumptive positive cases of COVID-19 ([^\n]+)\n/
      h[:positive] += $1.to_i
    else
      @errors << "missing presumptive positive"
    end
    # TODO parse quarantined and monitored
    h
  end # parse_ma

  def parse_md(h)
    if @s =~ />Number of patients tested for COVID-19: ([^<]+)</
      h[:tested] = $1.to_i
    else
      @errors << "missing tested"
    end
    if @s =~ />Number of COVID-19 tests pending: ([^<]+)</
      h[:pending] = $1.to_i
    else
      @errors << "missing pending"
      h[:pending] = 0
    end
    if @s =~ /Number of negative COVID-19 tests: ([^<]+)</
      h[:negative] = $1.to_i
    else
      @errors << "missing negative"
    end
    if @s =~ /Number of positive COVID-19 tests: ([^<]+)</
      h[:positive] = $1.to_i
    else
      @errors << "missing cases"
    end
    h[:tested] = h[:positive] + h[:negative] + h[:pending].to_i unless h[:tested]
    h
  end

  def parse_me(h)
    cols = @doc.css('table')[0].text.split("\n").map {|i| i.strip}.select {|i| i.size > 0}
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Total Confirmed Cases/}.first
      h[:positive] = string_to_i(cols[x[1]+4])
    else
      @errors << 'missing positive'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Total Presumptive Positive Cases/}.first
      h[:positive] += string_to_i(cols[x[1]+4])
    else
      @errors << 'missing positive 2'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Persons With Tests Pending/}.first
      h[:pending] = string_to_i(cols[x[1]+4])
    else
      @errors << 'missing pending'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Persons With Negative Tests/}.first
      h[:negative] = string_to_i(cols[x[1]+4])
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
    rows = @doc.css('table')[0].text.split("\n").map {|i| i.strip}.select {|i| i.size > 0}
    if i = rows.find_index("Positive")
      h[:positive] = rows[i+1].to_i
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
    h
  end  

  def parse_mo(h)
    if @s =~ />Presumptive Positive cases in Missouri: ([^<]+)</
      h[:positive] = $1.to_i
    else
      @errors << "missing cases"
    end
    h
  end

  def parse_ms(h)
    if @s =~ /Mississippi confirmed cases: <strong>([^<]+)</
      h[:positive] = $1.to_i
    else
      @errors << "missing cases"
    end
    if @s =~ />Updated ([^<]+)</
      h[:date] = $1
    else
      @errors << "missing date"
    end
    if @s =~ /Individuals tested by the MSDH Public Health Laboratory: <strong>([^<]+)<.*as of ([^<]+)</
    #if @s =~ /Individuals tested by the MSDH Public Health Laboratory as of([^:]+): <strong>([^<]+)</
      h[:tested] = string_to_i($1)
      h[:date_tested] = $2
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
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/Persons with positive results/}.first
      h[:positive] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing positive'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/Persons with negative results/}.first
      h[:negative] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing negative'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/Persons tested for CoVID-19\*/}.first
      h[:tested] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing tested'
    end
    h
  end  

  def parse_nc(h)
    if @s =~ /Updated: (.*) Presumptive Positive - A positive/
      h[:date] = $1
    else
      @errors << 'missing date'
    end
    rows = @doc.css('table')[0].text.split("\n").map {|i| i.strip}.select {|i| i.size>0}
    h[:positive] = 0
    if i = rows.find_index("Presumptive Positive")
      h[:positive] = rows[i+1].to_i
    else
      @errors << "missing presumptive positive"
    end
    if i = rows.find_index("Confirmed Positive")
      h[:positive] += rows[i+1].to_i
    else
      @errors << "missing confirmed positive"
    end
    h
  end

  def parse_nd(h)
    # TODO weird js
    puts "challenging js for nd"
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
    cols = @doc.css('table')[0].text.split("\n").map {|i| i.strip}.select {|i| i.size > 0}
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/Number of Persons Confirmed/}.first
      h[:positive] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing positive'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/Number of Persons Presumptive Positive/}.first
      h[:positive] += string_to_i(cols[x[1]+1])
    else
      @errors << 'missing positive 2'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/Number of Persons with Test Pending/}.first
      h[:pending] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing pending'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/Number of Persons Tested \(closed, tested negative\)/}.first
      h[:negative] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing negative'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/Total Number of Persons Provided Specimens/}.first
      h[:tested] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing tested'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/Number of Persons Being Monitored/}.first
      h[:monitored] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing monitored'
    end
    if @doc.text =~ /New Hampshire 2019 Novel Coronavirus \(COVID-19\) Summary Report \r\n\t  \(updated ([^\)]+)\)/
      h[:date] = $1
    else
      @errors << "missing date"
    end
    h
  end

  def parse_nj(h)
    rows = @doc.css('table')[0].text.split("\n").select {|i| i.strip.size >0}
    if i = rows.find_index("Negative")
      h[:negative] = rows[i+1].to_i
    else
      @errors << "missing negative"
    end
    if i = rows.find_index("PresumptivePositive*")
      h[:positive] = rows[i+1].to_i
    else
      @errors << "missing positive"
    end
    if i = rows.find_index("CDC Confirmed Positive")
      h[:positive] += rows[i+1].to_i
    else
      @errors << "missing positive2"
    end
    if i = rows.find_index("Total")
      h[:tested] = rows[i+1].to_i
    else
      @errors << "missing tested"
    end
    if i = rows.find_index("Tests inProcess")
      h[:pending] = rows[i+1].to_i
      h[:tested] += h[:pending]
    else
      @errors << "missing pending"
    end
    if i = rows.find_index("Persons underinvestigation (PUI)")
      h[:pui] = rows[i+1].to_i
    else
      @errors << "missing pui"
    end
    if i = rows.find_index("Positive testsfrom commerciallaboratories")
      h[:positive] += (x=rows[i+1].to_i)
      h[:tested] += x
    else
      @errors << "missing positive commercial"
    end
    h
  end

  def parse_nm(h)
    @driver.navigate.to @url
    sleep(3)
    rows = @driver.find_elements(class: "et_pb_text_inner").map {|i| i.text}.select {|i| i=~/COVID-19 Test Results in New Mexico/}[0].split("\n")
    if rows[1] =~ /As of end-of-day ([^\–]+)/
      h[:date] = $1.strip
    else
      @errors << 'missing date'
    end
    cols = rows[2].split(" ")
    if cols[0] == 'Positive'
      h[:positive] = cols[-1].to_i
    else
      @errors << "missing positive"
    end
    cols = rows[3].split(" ")
    if cols[0] == 'Negative'
      h[:negative] = cols[-1].to_i
    else
      @errors << "missing negative"
    end
    cols = rows[4].split(" ")
    if cols[0] == 'Total'
      h[:tested] = cols[-1].to_i
    else
      @errors << "missing tested"
    end
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
    if @s =~ /<em>Last Updated: ([^\s]+) <\/em><\/strong><\/span>/
      h[:date] = $1
    else
      @errors << "missing date"
    end
    h
  end

  def parse_ok(h)
    cols = @doc.css('table').map {|i| i.text}.select {|i| i=~/Oklahoma Test Results/}.last.split("\r").select {|i| i.strip.size > 0}
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/Positive \(Confirmed\)/}.first
      h[:positive] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing positive'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/Positive \(Presumptive/}.first
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
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/Total Tested/}.first
      h[:tested] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing tested'
    end
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
    cols = @driver.find_elements(class: "ms-rteTable-default").map {|i| i.text}.select {|i| i=~/Presumptive/}.first.split("\n")
rescue => e
  byebug
  puts
end
    if @s =~ />PA COVID-19 Update – ([^<]+)</
      h[:date] = $1.strip
    else
      @errors << "missing date"
    end
    if cols[0..2] == ["Persons Under Investigation (PUIs)", "Negative Pending Presumptive Positive", "Confirmed Positive"] 
      x = cols[3].split(" ").map {|i| string_to_i(i)}
      h[:pui] = x[0]
      h[:negative] = x[1]
      h[:pending] = x[2]
      h[:positive] = x[3]
      h[:positive] += x[4]
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
    if @s =~ /Last Update: ([^\n]+)\n/
      h[:date] = $1
    else
      @errors << 'missing date'
    end
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
      h[:positive] += string_to_i(rows[i+1])
    else
      @errors << "missing positive"
    end
    h[:pending] = 0
    h[:tested] = h[:positive] + h[:negative]
    h
  end

  def parse_sd(h)
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
    h
  end  

  def parse_tn(h)
    cols = @doc.css('table')[0].text.split("\n").map {|i| i.strip}.select {|i| i.size > 0}
    if cols.size != 6
      byebug
    end
    h[:pending] = 0
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/Number Positive/}.first
      h[:positive] = string_to_i(cols[x[1]+3])
    else
      @errors << 'missing positive'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/Number Negative/}.first
      h[:negative] = string_to_i(cols[x[1]+3])
    else
      @errors << 'missing negative'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/Total State Laboratory Tests Completed/}.first
      h[:tested] = string_to_i(cols[x[1]+3])
    else
      @errors << 'missing tested'
    end
    h
  end

  def parse_tx(h)
    # TODO each row is # of cases for a county, only parsing Total currently 
    rows = @doc.css('table')[0].text.split("\n").map {|i| i.strip}
    if ind = rows.find_index('Total')
      h[:positive] = rows[ind+1].to_i
    else
      @errors << "tx" unless rows[-2] == 'Total'
    end
    h
  end # parse_tx  

  def parse_ut(h)
    if @s =~ /Currently, there are two confirmed case of COVID-19 in Utah/
      h[:positive] = 2
    else
      @errors << 'ut: more than 2 case'
    end
    h
  end # parse_ut

  def parse_va(h)
    if @s =~ /Number of Presumptive Positive or Confirmed Cases:([^<]+)</
      h[:positive] = string_to_i($1)
    else
      @errors << 'missing positive'
    end
    if @s =~ /Number of Negative COVID-19 Tests:([^<]+)</
      h[:negative] = string_to_i($1)
      h[:tested] = h[:positive] + h[:negative]
      h[:pending] = 0
    else
      @errors << 'missing negative'
    end
    h
  end  

  def parse_vt(h)
    if @s =~ />\nLast updated: ([^<]+)</
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
    cols = @driver.find_elements(class: 'pane_layout').map {|i| i.text}.select {|i| i=~ /Total Tests/}[0].split("\n").map {|i| i.strip}.select {|i| i.size > 0}
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
    if @s =~ /<p><em>Last updated: (.+)\.</
      h[:date] = $1
    else
      @errors << "missing date"
    end
=begin
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
    else
      @errors << "missing recovered"
    end
    h
  end # parse_wi

  def parse_wv(h)
    if @s =~ /As of ([^,]+,[^,]+), West Virginia has tested ([^\s]+) residents for COVID-19\; ([^\s]+) were negative and ([^\s]+) are pending.*No cases have been/
      h[:date] = $1.strip
      h[:tested] = string_to_i($2)
      h[:negative] = string_to_i($3)
      h[:pending] = string_to_i($4)
      h[:positive] = h[:tested] - h[:negative] - h[:pending]
    else
      @errors << 'parse failed'
    end
    h
  end

  def parse_wy(h)
    if @s =~ /At this time there are no reported cases in Wyoming/
      h[:positive] = 0
    else
      @errors << "cases found"
    end
    h
  end

  ######################################

  def string_to_i(s)
    return s if s.class == Integer
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
        s.strip.gsub('‡','').gsub(',','').to_i
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

      skip_flag = false if @st == OFFSET
      next if skip_flag

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
      if (tested_new != h[:tested] || count == 3 || (count == 4 && (h[:tested] != (h[:positive] + h[:negative] + h[:pending])))) && !h[:skip]
        puts "please double check stats"
        puts h.inspect
        @driver.navigate.to(@url) rescue nil
        byebug
        puts 'here'
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
      end

      if DEBUG_PAGE_FLAG
        @driver.navigate.to @url
        puts
        puts @st
        puts h.inspect
        puts
        puts({:tested => h[:tested], :pos => h[:positive], :neg => h[:negative], :pending => h[:pending]}.inspect)
        byebug
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
