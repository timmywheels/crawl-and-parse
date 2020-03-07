require 'byebug'
require 'nokogiri'
require "selenium-webdriver"

DEBUG_ST = nil

class Crawler

  def parse_ak(h)
    if @s =~ /Updated ([^;]+); updates made daily by 12:30pm<\/em><\/p><\/div>\r\n<h4>Confirmed cases<\/h4>\r\n<ul><li><strong>Current: ([^<]+)<\/strong><\/li>\r\n<li>Cumulative since 1\/1\/2020: ([^<]+)</
      h[:date] = $1
      h[:current] = $2
      h[:cases] = $3.to_i 
    else
      @errors << "missing cases"
    end
    if @s =~ /Persons Under Investigation \(PUI\)\*<\/a><\/h4>\r\n<ul><li><strong>Current: ([^\s]+) \(pending tests\)<\/strong><\/li>\r\n<li>Cumulative since 1\/1\/2020: ([^\s]+) /
      h[:pui] = $1.to_i
      h[:tested] = $2.to_i
    else
      @errors << "missing pui"
    end
    h
  end

  def parse_ar(h)
    rows = @doc.css('table')[0].text.split("\n").map {|i| i.strip}.select {|i| i.size > 0}
    if rows[0] =~ /Status Update as of (.+)/
      h[:date] = $1
      h[:cases] = rows[-1].to_i
    else
      @errors << "missing date"
    end
    rows = @doc.css('table')[1].text.split("\n").map {|i| i.strip}.select {|i| i.size > 0}
    h[:pui] = rows[-1].to_i
    rows = @doc.css('table')[2].text.split("\n").map {|i| i.strip}.select {|i| i.size > 0}
    h[:monitored] = rows[-1].split("\s")[0].to_i
    rows = @doc.css('table')[3].text.split("\n").map {|i| i.strip}.select {|i| i.size > 0}
    h[:pui_past] = rows[-1]
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
      byebug # manually save
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
      if rows[0][0] != "Number of People Tested"
        @errors << "missing tested"
      end
      h[:confirmed] = rows[1][1]
      if rows[1][0] != "Number of Confirmed Positive"
        @errors << "missing confirmed"
      end
      h[:presumptive] = rows[2][1]
      if rows[2][0] != "Number of Presumptive Positive"
        @errors << "missing presumptive"
      end
      h[:pui] = rows[3][1].to_i
      if rows[3][0] != "Number of Pending"
        @errors << "missing pending"
      end
      rows = open('/Users/danny/Downloads/Cases_crosstab.csv').readlines.map {|i| i.strip.split("\t")}
      h[:cases] = rows[3][1].to_i + rows[3][2].to_i
      if rows[3][0] != "Total Cases"
        @errors << "missing cases"
      end
      h[:deaths] = rows[4][1].to_i + rows[4][2].to_i
      if rows[4][0] != "Total Deaths"
        @errors << "missing deaths"
      end
      `mv /Users/danny/Downloads/Cases_crosstab.csv #{@path}az/#{Time.now.to_s[0..18].gsub(' ','_')}_Cases_crosstab.csv`
      `mv /Users/danny/Downloads/Testing_crosstab.csv #{@path}az/#{Time.now.to_s[0..18].gsub(' ','_')}_Testing_crosstab.csv`
    rescue => e
      byebug
      @errors << "az failed"
    end
    h
  end # parse_az

  def parse_ca(h)
    @s.gsub!("&#160;",'')
    if @s =~ /As of(.+), there are a total of(.+)positivecases and(.+)death in California:(.+)cases are from repatriation flights. The other(.+)confirmed cases include(.+)that are travel related,(.+)due to person-to-person exposure fromfamily contact,(.+)due to person-to-person exposure in a health care facility,(.+)community acquired and(.+)from unknown sources/
      h = {
        :date => $1,
        :st => @st,
        :cases => string_to_i($2),
        :deaths => string_to_i($3),
        :case_repatriation => string_to_i($4),
        :case_other => string_to_i($5),
        :case_other_travel => string_to_i($6),
        :case_other_family => string_to_i($7),
        :case_other_healthcare => string_to_i($8),
        :case_other_community => string_to_i($9),
        :case_unknown => string_to_i($10),
        :ts => Time.now
      }
    else # regex doesn't match
      @errors << "CA not parsed"
      h[:s] = @s
    end
    h
  end

  def parse_co(h)
    rows = @doc.css('table')[0].text.split("\n").map {|i| i.strip}.select {|i| i.size > 0}
    if rows[0] == "Positive"
      h[:cases] = rows[1].to_i
      h[:negative] = rows[3]
      h[:pui] = rows[5].to_i
      h[:tested] = rows[7].to_i
    else
      @errors << "missing positive"
    end
    h
  end

  def parse_de(h)
    # TODO only image at: https://dhss.delaware.gov/dhss/dph/epi/images/coronavirusstats.jpg
    @driver.navigate.to @url
    puts "only image for DE"
    byebug
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
        end
        h[:cases] = 0
        if @s =~ /\n([^\s]+) – Florida Residents\n/
          h[:cases] += $1.to_i
        end
        if @s =~ /\n([^\s]+) – Florida Resident Presumptive Positive\n/
          h[:cases] += $1.to_i
        end
        if @s =~ /\n([^\s]+) – Florida Cases Repatriated\n/
          h[:cases] += $1.to_i
        end
        if @s =~ /\n([^\s]+) – Non-Florida resident\n/
          h[:cases] += $1.to_i
        end
        if @s =~ /\n Number of Negative Test Results\n([^\s]+)\n/
          h[:negative] = $1.to_i
        end
        if @s =~ /\n Number of Pending Testing Results\n([^\s]+)\n/
          h[:pending] = $1.to_i
        end
        if @s =~/\n Number of People Under Public Health Monitoring\n([^\s]+) – currently being monitored\n([^\s]+) – people monitored to date\n/
          h[:pui] = $1.to_i
          h[:monitored_all] = $2
        end
        h[:tested] = h[:cases] + h[:negative] + h[:pending]
      else
        @errors << "fl"
      end
    rescue
      @errors << "fl2"
    end
    h
  end # parse_fl

  def parse_ga(h)
    # TODO link
    @driver.navigate.to @url
    puts "link has no data for GA"
    byebug
    h
  end

  def parse_hi(h)
    rows = @doc.css('table')[0].text.gsub(" ",' ').split("\n").map {|i| i.strip}.select {|i| i.size > 0}
    if rows[0] == "Number of Confirmed Case(s)" && rows.size == 10
      h[:cases] = rows[1].to_i
      h[:pui] = rows[3].to_i
      h[:pui_neg] = rows[5]
      h[:quarantine] = rows[7].to_i
      h[:monitored] = rows[9].to_i
      h[:pui] += (h[:quarantine] + h[:monitored])
    else
      @errors << 'bad table'
    end
    h
  end

  def parse_ia(h)
    # TODO
    @driver.navigate.to @url
    puts "stats are in image in ia"
    byebug
    h
  end

  def parse_id(h)
    @driver.navigate.to @url
    rows = @driver.find_elements(class: "wp-block-table")[0].text.split("\n")
    if rows[3] =~ /^Number of confirmed/
      h[:cases] = rows[3].split("\s").last.to_i
      h[:monitored] = rows[0].split("\s").last.to_i
      h[:monitored_done] = rows[1].split("\s").last.to_i
      h[:tested] = rows[2].split("\s").last.to_i
    else
      @errors << "missing confirmed"
    end
    h
  end

  def parse_il(h)
    rows = @doc.css('table')[0].text.split("\n").select {|i| i.size > 0}
    if rows[1] == "Positive (confirmed)" && rows[3] == "Presumptive Positive, pending confirmation at CD"
      h[:cases] = rows[2].to_i + rows[4].to_i
    else
      @errors << "missing cases"
    end
    if rows[5] == "Negative"
      h[:negative] = rows[6].to_i
    else
      @errors << "missing negative"
    end
    if rows[7] == "PUIs Pending"
      h[:pending] = rows[8].to_i
    else
      @errors << "missing pending"
    end
    if rows[9] == "Total PUI"
      h[:tested] = rows[10].to_i
    else
      @errors << "missing tested"
    end
    h
  end # parse_il  

  def parse_ma(h)
    @driver.navigate.to @url
    s = @driver.find_elements(class: "ma__rich-text ").map {|i| i.text}.select {|i| i=~/confirmed cases/}[-1]

    if s =~ /COVID-19 cases in Massachusetts as of ([^*]+)/
      h[:date] = $1
    else
      @errors << "missing date"
    end
    if s =~ /\nTotal confirmed cases of COVID-19 ([^\n]+)\n/
      h[:cases] = $1.to_i
    else
      byebug
      @errors << "missing cases"
    end
    if s =~ /\nTotal presumptive positive cases of COVID-19 ([^\n]+)\n/
      h[:cases] += $1.to_i
    else
      @errors << "missing presumptive positive"
    end
    # TODO parse quarantine and monitored
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
      h[:cases] = $1.to_i
    else
      @errors << "missing cases"
    end
    h
  end

  def parse_mi(h)
    rows = @doc.css('table')[0].text.gsub(" "," ").split("\n").map {|i| i.strip}.select {|i| i.size > 0}
    if rows[6] == "Positive for 2019-nCoV"
      h[:date] = rows[1]
      h[:pui] = rows[3].to_i
      h[:negative] = rows[5].to_i
      h[:cases] = rows[7].to_i
      h[:pending] = rows[9].to_i
      h[:monitored_all] = rows[11].to_i
      h[:monitored] = rows[13].to_i
      h[:tested] = h[:negative] + h[:cases] + h[:pending]
    else
      @errors << "missing positive"
    end
    h
  end

  def parse_mn(h)
    rows = @doc.css('table')[0].text.split("\n").map {|i| i.strip}.select {|i| i.size > 0}
    if rows[4] == 'Total'
      h[:cases] = rows[1].to_i
      h[:negative] = rows[3].to_i
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
    if @s =~ /Laboratory-confirmed  cases in Missouri: ([^<]+)</
      h[:cases] = $1.to_i
    else
      @errors << "missing cases"
    end
    h
  end

  def parse_ms(h)
    if @s =~ /Mississippi confirmed cases: <strong>([^<]+)</
      h[:cases] = $1.to_i
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
    @driver.navigate.to @url
    puts "stats in image for mt"
    byebug
    h
  end  

  def parse_nc(h)
    # TODO link
    @driver.navigate.to @url
    puts "link has no data for nc"
    byebug
    h
  end

  def parse_nd(h)
    # TODO weird js
    @driver.navigate.to @url
    puts "challenging js for nd"
    byebug
    h
  end  

  def parse_ne(h)
    if @s =~ />Updated\&\#58\; <\/strong>([^<]+)</
      h[:date] = $1
    else
      @errors << "missing date"
    end
    if @s =~ /Nebraska Case Information<\/h2><ul><li>Number of confirmed cases – ([^<]+)<\/li><li>Case undergoing further testing at the Nebraska Public Health Lab - ([^<]+)<\/li><\/ul><ul><li>Cases that tested negative – ([^<]+)<\/li><\/ul><p>/
      h[:cases] = $1.to_i
      h[:negative] = $3.to_i
      h[:tested] = $2.to_i + h[:cases] + h[:negative]
    else
      @errors << "missing cases"
    end
    h
  end  

  def parse_nh(h)
    cols = @doc.css('table')[0].text.split("\n").map {|i| i.strip}.select {|i| i.size > 0}
    if cols.size == 10 && cols[0] == 'Total Number of Persons Tested' && cols[2] == "Number of Confirmed Case(s) 1"
      h[:tested] = cols[1].to_i
      h[:cases] = cols[3].to_i + cols[7].to_i
      h[:pending] = cols[5].to_i
      h[:negative] = cols[9].to_i
    else
      @errors << "nh"
    end
    h
  end

  def parse_nj(h)
    # TODO link
    @driver.navigate.to @url
    puts "no link for nj"
    byebug
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
      h[:cases] = cols[3].to_i
    else
      @errors << "missing cases"
    end
    if cols[4] == "Negative**"
      h[:negative] = cols[5].to_i
      h[:tested] = h[:cases] + h[:negative]
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
    else
      @errors << "missing pui_neg"
    end
    h
  end

  def parse_ny(h)
    if @doc.css('table')[0].text =~ /Data last updated (.+)\r/
      h[:date] = $1
    else
      @errors << "missing date"
    end
    cols = @doc.css('table')[0].css('tr')[1].text.gsub("\r",'').split("\n")
    if cols[1] != "Positive Cases"
      @errors << "row1"
    else
      h[:pos_outside_nyc] = cols[2].to_i
      h[:pos_nyc] = cols[3].to_i
      h[:cases] = h[:pos_outside_nyc] + h[:pos_nyc]
      h[:tested] = h[:cases]
      h[:persons_under_investigation] = cols[4].to_i
    end
    cols = @doc.css('table')[0].css('tr')[2].text.gsub("\r",'').split("\n")
    if cols[1] != "Negative Results\t"
      @errors << "row2"
    else
      h[:neg_outside_nyc] = cols[2].to_i
      h[:neg_nyc] = cols[3].to_i
      h[:tested] += h[:neg_outside_nyc] + h[:neg_nyc]
    end
    cols = @doc.css('table')[0].css('tr')[3].text.gsub("\r",'').split("\n")
    if cols[1] != "Pending Test Results\t"
      @errors << "row2"
    else
      h[:pending_outside_nyc] = cols[2].to_i
      h[:pending_nyc] = cols[3].to_i
      h[:tested] += h[:pending_outside_nyc] + h[:pending_nyc]
    end
    h
  end

  def parse_oh(h)
    rows = @doc.css('table')[0].text.split("\n").map {|i| i.strip }.select {|i| i.size > 0}
    if rows[1] =~ /in Ohio: (.+)/
      h[:cases] = $1.to_i
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
      h[:cases] = rows[3].to_i
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
      h[:pum_current] = x[1].to_i
      x = @doc.css('table')[1].css('tr')[2].text.gsub("\r",'').split("\n")
      h[:pum_complete] = x[-1].to_i
      x = @doc.css('table')[1].css('tr')[3].text.gsub("\r",'').split("\n")
      h[:pum_total] = x[1].to_i
    rescue
      @errors << "failed to parse"
    end
    h[:cases] = h[:positive].to_i
    h
  end  

  def parse_ri(h)
    @driver.navigate.to @url
    sleep(3)
    if @driver.find_elements(class: 'panel').select {|i| i.text =~ /Both individuals were on the same European trip. Being informed is an important part of being prepared. Learn more about how to prevent the spread in your community.\n\nSomeone/ }.size > 0
      h[:cases] = 2
    else
      @errors << 'ri'
    end
    h
  end

  def parse_sd(h)
    rows = @doc.css('table')[0].text.split("\n").map {|i| i.strip}.select {|i| i.size > 0}
    if rows[0] == "Positive*"
      h[:cases] = rows[1].to_i
      h[:tested] = h[:cases]
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
    h
  end  

  def parse_tx(h)
    # TODO each row is # of cases for a county, only parsing Total currently 
    rows = @doc.css('table')[0].text.split("\n").map {|i| i.strip}
    if ind = rows.find_index('Total')
      h[:cases] = rows[ind+1].to_i
    else
      @errors << "tx" unless rows[-2] == 'Total'
    end
    h
  end # parse_tx  

  def parse_ut(h)
    @driver.navigate.to @url
    if @s =~ /s first case of COVID-19 on March 6, 2020. This is currently the only case in Utah/
      h[:cases] = 1
    else
      @driver.navigate.to @url
      puts "more than 1"
      byebug
      @errors << 'ut'
    end
    h
  end # parse_ut

  def parse_va(h)
    # TODO js without csv download, only pdf download
    @driver.navigate.to @url
    puts "js with pdf download for va"
    byebug
    h
  end  

  def parse_wa(h)
    if @s =~ /federal quarantine guidance<\/a>.<\/p>\n   <\/div>\n   <\/th>\n  <\/tr>\n <\/tbody>\n<\/table>\n\n<p><em>Last updated: (.+)\.</
      h[:date] = $1
    else
      @errors << "missing date"
    end
    i = (@s =~ /Number of people under public health supervision/)
    if i
      if @s[i..(i+1000)].split("\n")[1] =~ /<td>(.+)<\/td>/
        h[:public_health_supervision] = $1
      else
        @errors << "missing 1"
      end
    else
      @errors << "missing 2"
    end
    rows = @doc.css('table')[0].text.split("\n").map {|i| i.strip}.select {|i| i.size > 0}
    if rows[-3] == 'Total'
      h[:cases] = rows[-2].to_i
      h[:deaths] = rows[-1].to_i
    else
      @errors << "missing totals"
    end    
    h
  end

  def parse_wi(h)
    rows = @doc.css('table')[0].text.split("\n").map {|i| i.strip}
    if rows[2] == "Positive"
      h[:cases] = rows[3].to_i
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
      s.to_i
    end
  end

  def initialize
    @driver = Selenium::WebDriver.for :firefox
    @path = 'data/'
  end

  def method_missing(m, h)
    puts "skipping state: #{@st}"
    h
  end

  def run
    errors_crawl = []
    positive = {:all => 0}
    deaths   = {:all => 0}
    pui      = {:all => 0}
    tested   = {:all => 0}

    for @st, @url in (open('states.csv').readlines.map {|i| i.strip.split("\t")}.map {|st, url| [st.downcase, url]})
      next unless @st == DEBUG_ST if DEBUG_ST
      `mkdir -p #{@path}#{@st}`
      @s = `curl -s #{@url}`
      @doc = Nokogiri::HTML(@s)
      @errors = []
      h = {:ts => Time.now, :st => @st}
      h = send("parse_#{@st}", h)
      open("#{@path}#{@st}/#{Time.now.to_s[0..18].gsub(' ','_')}", 'w') {|f| f.puts @s}

      if false # for debugging
        @driver.navigate.to @url
        puts @st
        puts h.inspect
        byebug
      end

      positive[:all] += h[:cases].to_i
      positive[@st.to_sym] = h[:cases]

      deaths[:all] += h[:deaths].to_i
      deaths[@st.to_sym] = h[:deaths]

      pui[:all] += h[:pui].to_i
      pui[@st.to_sym] = h[:pui]

      tested[:all] += h[:tested].to_i
      tested[@st.to_sym] = h[:tested]

      h[:error] = @errors
      puts "error in #{@st}! #{@errors.inspect}" if @errors.size != 0
      errors_crawl << @st if @errors.size != 0
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
    
    open('stats.csv','w') {|f| f.puts tested.to_a.map {|st, v| [st.to_s, v, positive[st], deaths[st]].join("\t")}.sort}

  end # end run

end # end Crawler class
