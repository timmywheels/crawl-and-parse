require 'byebug'
require 'nokogiri'
require "selenium-webdriver"

USER_FLAG = true # user enters missing data (in images, js, etc)
DEBUG_FLAG = true # saves output to "debug/" dir
DEBUG_PAGE_FLAG = false # review each webpage manually

DEBUG_ST = nil  # run for a single state

class Crawler

  def parse_al(h)
    if @s =~ /At this time, no COVID-19 cases have been identified in Alabama/
      h[:positive] = 0
    else
      @errors << "cases found"
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
      h[:tested] = $2.to_i
      h[:pui_cumulative] = h[:tested]
    else
      @errors << "missing pui"
    end
    h
  end

  def parse_ar(h)
    rows = @doc.css('table')[0].text.split("\n").map {|i| i.strip}.select {|i| i.size > 0}
    if rows[0] =~ /Status Update as of (.+)/
      h[:date] = $1
      h[:positive] = rows[-1].to_i
    else
      @errors << "missing date"
    end
    rows = @doc.css('table')[1].text.split("\n").map {|i| i.strip}.select {|i| i.size > 0}
    h[:pui] = rows[-1].to_i
    rows = @doc.css('table')[2].text.split("\n").map {|i| i.strip}.select {|i| i.size > 0}
    h[:monitored] = rows[-1].split("\s")[0].to_i
    s = (@doc.css('table')[3].text.split("\n").map {|i| i.strip}.select {|i| i.size > 0})[-1]
    if s.gsub(',','') =~ /([0-9]+) negative test/
      h[:tested] = $1.to_i
      h[:pui_cumulative] = h[:tested]
    else
      @errors << "missing tested"
    end
    h
  end

  def parse_az(h)
    begin
      `rm /Users/danny/Downloads/Testing_crosstab.csv`
      `rm /Users/danny/Downloads/Cases_crosstab.csv`
      @driver.navigate.to @url
      sleep(5)
      @driver.find_elements(class: "tvimagesContainer")[0].click
      @driver.find_elements(class: "download")[0].click
      x = @driver.find_elements(class: "tab-downloadDialog")[0]
      x.find_elements(:css, "*")[3].click
      @driver.find_elements(class: "tabDownloadFileButton")[0].click
      byebug # manually save, required to set browser preferences
      @driver.find_elements(class: "tvimagesContainer")[15].click
      @driver.find_elements(class: "download")[0].click
      x = @driver.find_elements(class: "tab-downloadDialog")[0]
      x.find_elements(:css, "*")[3].click
      @driver.find_elements(class: "tabDownloadFileButton")[0].click
      sleep(2)
      `dos2unix /Users/danny/Downloads/Testing_crosstab.csv`
      `dos2unix /Users/danny/Downloads/Cases_crosstab.csv`
      rows = open('/Users/danny/Downloads/Testing_crosstab.csv').readlines.map {|i| i.strip.split("\t")}
      h[:tested] = rows[0][1].to_i
      h[:pui_cumulative] = h[:tested]
      if rows[0][0] != "Number of People Tested"
        @errors << "missing tested"
      end
      h[:confirmed] = rows[1][1].to_i
      if rows[1][0] != "Number of Confirmed Positive"
        @errors << "missing confirmed"
      end
      h[:presumptive] = rows[2][1].to_i
      if rows[2][0] != "Number of Presumptive Positive"
        @errors << "missing presumptive"
      end
      h[:pui] = rows[3][1].to_i
      if rows[3][0] != "Number of Pending"
        @errors << "missing pending"
      end
      rows = open('/Users/danny/Downloads/Cases_crosstab.csv').readlines.map {|i| i.strip.split("\t")}
      h[:positive] = rows[3][1].to_i + rows[3][2].to_i
      if rows[3][0] != "Total Cases"
        @errors << "missing cases"
      end
      h[:deaths] = rows[4][1].to_i + rows[4][2].to_i
      if rows[4][0] != "Total Deaths"
        @errors << "missing deaths"
      end
      if @driver.find_elements(class: "tab-tvTitle")[0].text.strip =~ /Data last updated \| (.+)/
        h[:date] = $1
      else
        @errors << "missing date"
      end
      `mv /Users/danny/Downloads/Cases_crosstab.csv #{@path}az/#{Time.now.to_s[0..18].gsub(' ','_')}_Cases_crosstab.csv`
      `mv /Users/danny/Downloads/Testing_crosstab.csv #{@path}az/#{Time.now.to_s[0..18].gsub(' ','_')}_Testing_crosstab.csv`
    rescue => e
      @errors << "az failed: #{e.inspect}"
    end
    h
  end # parse_az

  def parse_ca(h)
    @s.gsub!("&#160;",'')
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
    else # regex doesn't match
      @errors << "CA not parsed"
      h[:s] = @s
    end
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
    if @s =~ />UPDATED: <\/span><span class=\"[^"]*\">([^<]+)</
      h[:date] = $1.strip
    else
      @errors << "missing date"
    end
    if @doc.css('table')[0].text.gsub(',','') =~ /Positive([0-9]+)Negative([0-9]+)Total tests\*([0-9]+)/
      h[:positive] = $1.to_i
      h[:negative] = $2.to_i
      h[:tested] = $3.to_i
    else
      @errors << "missing tests"
    end
    h
  end

  def parse_ct(h)
    if @s =~ /There are no confirmed cases in Connecticut at this time/
      h[:positive] = 0
    else
      @errors << "missing cases"
    end
    h
  end

  def parse_dc(h)
    @driver.navigate.to @url
    @s = @driver.find_elements(class: 'field-items')[0].text
    if @s.gsub(',','') =~ /Update: ([^\n]+)\nNumber of patients being monitored by DC Health and tested for COVID\-19 \(PUIs\): ([0-9]+)\nNumber of negative results: ([0-9]+)\nNumber of pending results: ([0-9]+)\nNumber of presumptive positive results: ([0-9]+)\nNumber of presumptive positive results from other lab: ([0-9]+)/
      h[:date] = $1.strip
      h[:pui] = $2.to_i
      h[:negative] = $3.to_i
      h[:pending] = $4.to_i
      h[:positive] = $5.to_i
      h[:positive_other_lab] = $6.to_i
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
      @s = @driver.find_elements(class: "wysiwyg_content")[-1].text
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
        if @s =~ /\n([^\s]+) – Florida Residents\n/
          h[:positive] += $1.to_i
        end
        if @s =~ /\n([^\s]+) – Florida Resident Presumptive Positive\n/
          h[:positive] += $1.to_i
        end
        if @s =~ /\n([^\s]+) – Florida Cases Repatriated\n/
          h[:positive] += $1.to_i
        end
        if @s =~ /\n([^\s]+) – Non-Florida resident\n/
          h[:positive] += $1.to_i
        end
        if h[:positive] < 13 # as of 3/7/2020
          @errors << "missing cases"
        end
        if @s =~ /\n Number of Negative Test Results\n([^\s]+)\n/
          h[:negative] = $1.to_i
        else
          @errors << "missing negative"
        end
        if @s =~ /\n Number of Pending Testing Results\n([^\s]+)\n/
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
    # TODO
    puts "link has no data for ga"
    if USER_FLAG
      @driver.navigate.to @url
      byebug
    end
    h
  end

  def parse_hi(h)
    if @s =~ />Update: On March 6, 2020 HDOH identified the first presumptive positive case of COVID-19 in Hawaii/
      h[:positive] = 1
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
    # TODO
    puts "stats are in image in ia"
    if USER_FLAG
      @driver.navigate.to @url
      byebug
    end
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
    rows = @doc.css('table').map {|i| i.text}.select {|i| i=~/Presumptive Positive, pending confirmation at CD/}[0].split("\n").select {|i| i.size > 0}
    if rows[1] == "Positive (confirmed)" && rows[3] == "Presumptive Positive, pending confirmation at CDC"
      h[:positive] = rows[2].to_i + rows[4].to_i
    else
      @errors << "missing cases"
    end
    if rows[5] == "Negative"
      h[:negative] = rows[6].to_i
    else
      @errors << "missing negative"
    end
    if rows[7] == "PUIs Pending"
      h[:pui] = rows[8].to_i
    else
      @errors << "missing pending"
    end
    if rows[9] == "Total PUI"
      h[:tested] = rows[10].to_i
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
    if @s =~ /United States. On March 6, ISDH <a href\=\"https:\/\/calendar.in.gov\/site\/isdh\/event\/state-health-department-confirms-1st-case-of-covid-19--in-hoosier-with-recent-travel\/\">confirmed<\/a>\&nbsp\;the first case/
      h[:positive] = 1
    else
      @errors << "failed to parse"
    end
    h
  end

  def parse_ky(h)
    if @s =~ /Current as of (.*) at&#160\;<br>4&#58\;30 p.m.&#160\;Eastern time<br><br>Kentucky Coronavirus Monitoring<\/strong><br>Number Tested&#58\; ([0-9]+)<br>Positive&#58\;&#160\;([0-9]+)&#160\;<br>Negative&#58\; ([0-9]+)</
      h[:date] = $1.strip
      h[:tested] = $2.to_i
      h[:positive] = $3.to_i
      h[:negative] = $4.to_i
    else
      @errors << "parse failed"
    end
    h
  end

  def parse_la(h)
    if @s =~ /There are no confirmed cases of COVID/
      h[:positive] = 0
    else
      @errors << "missing cases"
    end
    h
  end

  def parse_ma(h)
    @driver.navigate.to @url
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
    end
    if @s =~ />Number of negative COVID-19 tests: ([^<]+)</
      h[:negative] = $1.to_i
    else
      @errors << "missing negative"
    end
    if @s =~ />Number of positive COVID-19 tests: ([^<]+)</
      h[:positive] = $1.to_i
    else
      @errors << "missing cases"
    end
    h
  end

  def parse_me(h)
    if @s =~ /There are no confirmed cases of COVID-19 in Maine at this time/
      h[:positive] = 0
    else
      @errors << "missing cases"
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
    if rows[4] == 'Total'
      if rows[0] == 'Positive'
        h[:positive] = rows[1].to_i
      else
        @errors << 'missing pos'
      end
      if rows[2] == 'Negative'
        h[:negative] = rows[3].to_i
      else
        @errors << 'missing neg'
      end
      h[:tested] = rows[5].to_i
    else
      @errors << "missing total"
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
    h
  end

  def parse_mt(h)
    # TODO image at https://dphhs.mt.gov/portals/85/publichealth/images/CDEpi/DiseasesAtoZ/Coronavirus/COVID19table.png
    puts "stats in image for mt"
    if USER_FLAG
      @driver.navigate.to @url
      byebug 
    end
    h
  end  

  def parse_nc(h)
    # TODO link
    puts "link has no data for nc"
    if USER_FLAG
      @driver.navigate.to @url
      byebug 
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
    if @s =~ /Nebraska Case Information<\/h2><ul><li>Number of confirmed cases – ([^<]+)<\/li><li>Cases undergoing further testing at the Nebraska Public Health Lab - ([^<]+)<\/li><\/ul><ul><li>Cases that tested negative – ([^<]+)<\/li><\/ul><p>/
      h[:positive] = $1.to_i
      h[:negative] = $3.to_i
      h[:tested] = $2.to_i + h[:positive] + h[:negative]
    else
      @errors << "missing cases"
    end
    h
  end  

  def parse_nh(h)
    cols = @doc.css('table')[0].text.split("\n").map {|i| i.strip}.select {|i| i.size > 0}
    if cols.size == 10 && cols[0] == 'Total Number of Persons Tested' && 
      cols[2] == "Number of Confirmed Case(s) 1" &&
      cols[6] == "Number of Persons Tested (current, presumptive positive)3"
      h[:tested] = cols[1].to_i
      h[:positive] = cols[3].to_i + cols[7].to_i
      if cols[4] == "Number of Persons Being Tested (current, test pending) 2"
        h[:pending] = cols[5].to_i
      else
        @errors << 'missing pending'
      end
      if cols[8] == "Number of Persons Tested (closed, tested negative)"
        h[:negative] = cols[9].to_i
      else
        @errors << 'missing neg'
      end
    else
      @errors << "nh"
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
    if rows[2] == 'Negative'
      h[:negative] = rows[3].to_i
    else
      @errors << "missing negative"
    end
    if rows[4] == "PresumptivePositive*"
      h[:positive] = rows[5].to_i
    else
      @errors << "missing positive"
    end
    if rows[6] == "Total"
      h[:tested] = rows[7].to_i
    else
      @errors << "missing tested"
    end
    if rows[8] == "Tests inProcess"
      h[:pending] = rows[9].to_i
    else
      @errors << "missing pending"
    end
    if rows[10] == "PersonsUnderInvestigation(PUI)"
      h[:pui] = rows[11].to_i
    else
      @errors << "missing pui"
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
    h
  end

  def parse_nv(h)
    cols = @doc.css('table')[0].text.split("\n").map {|i| i.strip}.select {|i| i.size > 0}
    if cols[1] =~ /Last updated (.*)/
      h[:date] = $1
    else
      @errors << "missing date"
    end
    if cols[2] == "Positive"
      h[:positive] = cols[3].to_i
    else
      @errors << "missing cases"
    end
    if cols[4] == "Negative**"
      h[:negative] = cols[5].to_i
      h[:tested] = h[:positive] + h[:negative]
    else
      @errors << "missing negative"
    end
    if cols[10] == "Current"
      h[:pui] = cols[11].to_i
    else
      @errors << "missing pui"
    end
    if cols[12] =~ /PUM who have/
      h[:pui_neg] = cols[13].to_i
      h[:pui_cumulative] = h[:pui] + h[:pui_neg]
    else
      @errors << "missing pui_neg"
    end
    h
  end

  def parse_ny(h)
    begin
    if @doc.css('table')[0].text =~ /Data last updated (.+)\r/
      h[:date] = $1
    else
      @errors << "missing date"
    end
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
    rescue => e
      @errors << "rescue ny: #{e.inspect}"
    end
    h
  end

  def parse_oh(h)
    rows = @doc.css('table')[0].text.split("\n").map {|i| i.strip }.select {|i| i.size > 0}
    if rows[1] =~ /in Ohio: (.+)/
      h[:positive] = $1.to_i
    else
      @errors << "missing cases"
    end
    if rows[3] =~ /\(PUIs\)1 in Ohio: (.+)/
      h[:pui] = $1.to_i
    else
      @errors << "missing pui"
    end
    if rows[5] =~ /in Ohio: (.+)/
      h[:negative] = $1.to_i
    else
      @errors << "missing negative"
    end
    h[:tested] = h[:positive] + h[:pui] + h[:negative]
    if @s =~ /<em>Last Updated: ([^\s]+) <\/em><\/strong><\/span>/
      h[:date] = $1
    else
      @errors << "missing date"
    end
    rows = @doc.css('table')[1].text.split("\n").map {|i| i.strip }.select {|i| i.size > 0}
    if rows[1] =~ /Public Health Supervision3: (.+)4/ # 4 is a footnote
      h[:monitored] = $1.to_i
    else
      @errors << "missing monitoring"
    end
    h
  end

  def parse_ok(h)
    rows = @doc.css('table').map {|i| i.text}.select {|i| i=~/Oklahoma Test Results/}.last.split("\r").select {|i| i.strip.size > 0}
    if rows[2] == "Positive (Confirmed)"
      h[:positive] = rows[3].to_i
    else
      @errors << "missing cases"
    end
    if rows[4] == "Negative"
      h[:negative] = rows[5].to_i
    else
      @errors << "missing negative"
    end
    if rows[6] == "PUIs Pending Results"
      h[:pui] = rows[7].to_i
    else
      @errors << "missing pui"
    end
    if rows[8] == "Total Tested"
      h[:tested] = rows[9].to_i
    else
      @errors << "missing tested"
    end
    h
  end  

  def parse_or(h)
    begin
      x = @doc.css('table')[0].css('tr')[0].text.gsub("\r",'')
      if x =~ /Last updated (.*)/
        h[:date] = $1
      end
      x = @doc.css('table')[0].css('tr')[1].text.gsub("\r",'').split("\n")
      raise "positive" unless x[0] == "Positive"
      h[:positive] = x[1].to_i
      x = @doc.css('table')[0].css('tr')[2].text.gsub("\r",'').split("\n")
      raise "negative" unless x[0] == "Negative"
      h[:negative] = x[1].to_i
      x = @doc.css('table')[0].css('tr')[3].text.gsub("\r",'').split("\n")
      raise "pending" unless x[0] == "Pending"
      h[:pending] = x[1].to_i
      x = @doc.css('table')[0].css('tr')[4].text.gsub("\r",'').split("\n")
      h[:tested] = x[1].to_i
      x = @doc.css('table')[1].css('tr')[0].text.gsub("\r",'')
      if x =~ /Last updated (.*)/
        h[:pum_date] = $1
      end
      x = @doc.css('table')[1].css('tr')[1].text.gsub("\r",'').split("\n")
      raise "current" unless x[0] == 'Current'
      h[:pum_current] = x[1].to_i
      x = @doc.css('table')[1].css('tr')[2].text.gsub("\r",'').split("\n")
      raise "pum complete" unless x[0] == "PUM who have"
      h[:pum_complete] = x[-1].to_i
      x = @doc.css('table')[1].css('tr')[3].text.gsub("\r",'').split("\n")
      raise "pum total" unless x[0] =~ /Total PUM since /
      h[:pum_total] = x[1].to_i
      h[:pui] = h[:pum_current]
      h[:pui_cumulative] = h[:pum_total]
    rescue => e
      @errors << "failed to parse: #{e.inspect}"
    end
    h
  end  

  def parse_pa(h)
    if @s =~ />PA COVID-19 Update – ([^<]+)</
      h[:date] = $1.strip
    else
      @errors << "missing date"
    end
    if @s =~ />To date, there are&#160\;([^\s]+) presumptive positive cases of COVID-19 in Pennsylvania.</
      h[:positive] = $1.to_i
    else
      @errors << "parse failed"
    end
    h
  end

  def parse_ri(h)
    @driver.navigate.to @url
    sleep(5)
    if @driver.find_elements(class: 'panel').select {|i| i.text =~ /Both individuals were on the same European trip. Being informed is an important part of being prepared. Learn more about how to prevent the spread in your community.\n\nSomeone/ }.size > 0
      h[:positive] = 2
    else
      @errors << 'ri'
    end
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
    if @s =~ />This is currently the only case in Utah/
      h[:positive] = 1
    else
      @errors << 'ut: more than 1 case'
    end
    h
  end # parse_ut

  def parse_va(h)
    # TODO js without csv download, only pdf download
    puts "js with pdf download for va"
    if USER_FLAG
      @driver.navigate.to @url
      byebug 
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
    if rows[0] == "Vermonters being monitored"
      h[:pui] = rows[1].to_i
    else
      @errors << "missing monitored"
    end
    if rows[2] == "Vermonters who have completed monitoring"
      h[:pui_cumulative] = rows[3].to_i + h[:pui]
    else
      @errors << "missing pui cumulative"
    end
    if rows[4] == "Vermonters tested negative for COVID-19"
      h[:negative] = rows[5].to_i
    else
      @errors << "missing negative"
    end
    if rows[6] == "Vermont cases of COVID-19"
      h[:positive] = rows[7].to_i
    else
      @errors << "missing positive"
    end
    h[:tested] = h[:negative] + h[:positive]
    h
  end

  def parse_wa(h)
    if @s =~ /<p><em>Last updated: (.+)\.</
      h[:date] = $1
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
    if @doc.css('table')[0] && (rows = @doc.css('table')[0].text.split("\n").map {|i| i.strip}.select {|i| i.size > 0}) && rows[-3] == 'Total'
      # TODO parse each county
      h[:positive] = rows[-2].to_i
      h[:deaths] = rows[-1].to_i
    else
      @errors << "missing totals"
    end    
    h
  end

  def parse_wi(h)
    if @s =~ /\t\tAs of ([^<]+)<\/p>/
      h[:date] = $1.strip
    else
      @errors << "missing date"
    end
    rows = @doc.css('table')[0].text.split("\n").map {|i| i.strip}
    if rows[2] == "Positive"
      h[:positive] = rows[3].to_i
    else
      @errors << "missing cases"
    end
    if rows[4] == "Negative"
      h[:negative] = rows[5].to_i
    else
      @errors << "missing negative"
    end
    if rows[6] == "Pending"
      h[:pending] = rows[7].to_i
    else
      @errors << "missing pending"
    end
    if rows[8] == "Total"
      h[:tested] = rows[9].to_i
    else
      @errors << "missing tested"
    end
    h
  end # parse_wi

  def parse_wv(h)
    if @s =~ /<b>As of ([^,]+,[^,]+), West Virginia has tested ([^\s]+) residents for COVID-19\; ([^\s]+) were negative and ([^\s]+) are pending.\&#160\;No cases have been confirmed in West Virginia at this time/
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
      s.strip.gsub(',','').to_i
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

    for @st, @url in (open('states.csv').readlines.map {|i| i.strip.split("\t")}.map {|st, url| [st.downcase, url]})
      next unless @st == DEBUG_ST if DEBUG_ST
      `mkdir -p #{@path}#{@st}`
      @s = `curl -s #{@url}`
      @doc = Nokogiri::HTML(@s)
      @errors = []
      h = {:ts => Time.now, :st => @st, :source => @url}
      h = send("parse_#{@st}", h)
      open("#{@path}#{@st}/#{Time.now.to_s[0..18].gsub(' ','_')}", 'w') {|f| f.puts @s} # @s might be modified in parse

      positive[:all] += h[:positive].to_i
      positive[@st.to_sym] = h[:positive]

      deaths[:all] += h[:deaths].to_i
      deaths[@st.to_sym] = h[:deaths]

      pui[:all] += h[:pui].to_i
      pui[@st.to_sym] = h[:pui]

      tested[:all] += h[:tested].to_i
      tested[@st.to_sym] = h[:tested]

      h[:error] = @errors

      if @errors.size != 0
        puts "error in #{@st}! #{@errors.inspect}"
        errors_crawl << @st
        @driver.navigate.to @url
        byebug
      end

      if DEBUG_PAGE_FLAG
        @driver.navigate.to @url
        puts @st
        puts h.inspect
        byebug
      end
      h_all << h  
      # save parsed h
      open("#{@path}#{@st}.log",'a') {|f| f.puts h.inspect} if h && h.size > 0
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
