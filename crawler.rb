require 'byebug'
require 'nokogiri'
require "selenium-webdriver"

# TODO
# not automatic:
# ["az", "nd", "va"] 
# pdf for more data: ma, ny

SEC = 30 # seconds to wait for page to load
OFFSET = nil # if set, start running at that state
SKIP_LIST = [] # skip these states

=begin

Structure of the hash h, where STATE crawl data is stored

h = {
	:ts => Time.now, # timestamp of crawl
	:st => @st, # 2 letter STATE abbreviation
	:source_urls => [@url], # array of urls crawled
	:source_texts => [], # array of source text crawled
	:source_files => [], # array of filenames of pdfs or other files saved
	:tested => int,
	:positive => int,
	:negative => int,
	:pending => int,
	:deaths => int,
	:hospitalized => int,
	:recovered => int,
	:ts_tested => string, # update time of the specific data listed on the website
	:ts_positive => string,
	:ts_negative => string,
	:ts_pending => string,
	:ts_... # update time of other future fields
	:counties => [ { :name => string, 
	                 :tested => int, 
	                 :positive => int,
	                 :negative => int,
	                 :deaths => int }, ... ] # array of county specific fields, note that ts is for whole county
	:ts_counties => string
}

=end

class Crawler

  # parse_XXX methods for the 50 US states and DC

  def parse_ak(h)
    @driver.navigate.to @url
    cols = @doc.css('table').map {|i| i.text.gsub(',','')}.select {|i| i=~/Travel\-Related/}.first.split("\n").map {|i| i.strip}.select {|i| i.size>0}
    if cols[-4] =~ /TOTAL$/ 
      h[:positive] = string_to_i(cols[-1])
    else
      @errors << 'missing positive'
    end
    puts 'AK: tested data in image?'
    byebug unless @auto_flag
    h[:tested] # TODO
    # Cumulative number of cases hospitalized to date:  0​
    # positive by region available
    # no death data
    h
  end

  def parse_al(h)
    # @driver.navigate.to @url
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
    if @s.gsub(',','') =~ /Total Tested:([^<]+)/
      h[:tested] = string_to_i($1)
    else
      @errors << 'missing tested'
    end
    if @s.gsub(',','') =~ /Deaths:([^<]+)/
      h[:deaths] = string_to_i($1)
    else
      @errors << 'missing deaths'
    end
    # counties available
    h
  end

  def parse_ar(h)
    @driver.navigate.to(@url)
    @s = @driver.find_elements(id: 'contentBody')[0].text.gsub(',','')
    if @s =~ /\nConfirmed Cases of COVID-19 in Arkansas ([^\n]+)\n/
      h[:positive] = string_to_i($1)
    else
      @errors << 'missing positive'
    end
    if @s =~ /\nPersons Under Investigation \(PUI\) ([^\n]+)\n/
      h[:pending] = string_to_i($1)
    else
      @errors << 'missing pending'
    end
    if @s =~ /\nPast PUIs with negative test results ([^\n]+)\n/
      h[:negative] = string_to_i($1)
    else
      @errors << 'missing negative'
    end
    h
  end

  def parse_az(h)
    #@driver.navigate.to(@url) rescue nil
    #byebug
    if @auto_flag
      puts "skipping AZ"
      h[:skip] = true
      return h
    end
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
    if i = rows.select {|i| i[0] =~ /^Private Laboratory/}.first
      h[:tested] = 0 unless h[:tested]
      h[:tested] += string_to_i(i[1])
    else
      @errors << "missing private library tests"
    end
    `mv /Users/danny/Downloads/Testing_crosstab.csv #{@path}az/#{Time.now.to_s[0..18].gsub(' ','_')}_Testing_crosstab.csv`
    `mv /Users/danny/Downloads/Cases_crosstab.csv #{@path}az/#{Time.now.to_s[0..18].gsub(' ','_')}_Cases_crosstab.csv`
    h
  end # parse_az

  def parse_ca(h)
    @driver.navigate.to @url
    sec = SEC/5
    loop do
      @s = @driver.find_elements(id: 's4-workspace').first.text.gsub(/\s+/,' ')
      if @s =~ /there are a total of (.*) positive cases and (.*) deaths in California/
        h[:positive] = string_to_i($1)
        h[:deaths] = string_to_i($2)
        break
      elsif sec == 0
        @errors << 'CA parse failed'
        break
      end
      sec -= 1
      puts 'sleeping'
      sleep 1
    end
    # Negative from CDPH report of 778 tests on 3/7, and 88 pos => 690 neg
    #h[:negative] = 690 # TODO hard coded
    h
  end

  def parse_co(h)
    #@driver.navigate.to @url
    #byebug
    s = @doc.css('body').text.gsub(',','')
    if s =~ /\n([0-9]+)[^0-9]?cases\n([0-9]+)[^0-9]?hospitalized\n([0-9]+)[^0-9]?counties\n([0-9]+)[^0-9]?people tested\n([0-9]+)[^0-9]?deaths\n/
      h[:positive] = string_to_i($1)
      h[:hospitalized] = string_to_i($2)
      h[:tested] = string_to_i($4)
      h[:deaths] = string_to_i($5)
    else
      @errors << "parse failed"
    end
    # counties available
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
    @s = @driver.find_elements(id: 'page').first.text.gsub(',','').gsub(/\s+/,' ')
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
    if (x = @s.scan(/Number of PHL tests in progress: ([0-9]+)[^0-9]/)).size > 0
      h[:pending] = string_to_i(x[0][0])
    else
      @warnings << "pending missing"
    end
    h
  end

  def parse_de(h)
    # @driver.navigate.to @url
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
    if @driver.page_source =~ /"([^"]+)arcgis\.com([^"]+)"/
      url = $1 + 'arcgis.com' + $2
      @driver.navigate.to url
      sec = SEC
      url = nil
      loop do
        if @driver.page_source =~ /https:\/\/arcg.is([^"]+)"/
          url = 'https://arcg.is' + $1
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
      if url
        @driver.navigate.to(url)
        sec = SEC
        loop do
          @driver.find_elements(class: 'tab-title')[1].click
          s = @driver.find_elements(class: 'dashboard-page')[0].text
          if s =~ /\nTotal Tests\n([^\n]+)\n/
            h[:tested] = string_to_i($1)
            break
          elsif s == 0
            @errors << 'missing tested'
            break
          end
          sec -= 1
          puts 'sleeping'
          sleep 1
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
    #@driver.navigate.to @url
    #byebug
    @s = @doc.css('table')[0].text.gsub(',','')
    if @s =~ /\nTotal \(new\)\n([0-9]+)/
      h[:positive] = string_to_i($1)
    else
      @errors << 'missing positive'
    end
    @s = @doc.css('table')[0].text.gsub(',','')
    if @s =~ /\nDeaths\n([0-9]+)/
      h[:deaths] = string_to_i($1)
    else
      @errors << 'missing deaths'
    end
    # county cases
    h
  end

  def parse_ia(h)
    @driver.navigate.to @url
    if @driver.page_source =~ /<iframe src=\"https:\/\/iowa\.maps\.arcgis\.com([^"]+)"/
      @url = 'https://iowa.maps.arcgis.com' + $1
    else # might be captcha
      if @auto_flag
        @errors << 'missing dash url, possible captcha'
        return h
      end
      puts "check if captcha, missing @url"
      byebug
      nil
    end
    @driver.navigate.to @url
    sec = SEC/2
    loop do
      sec -= 1
      sleep 1
      puts 'sleeping'
      x = @driver.find_elements(class: 'dock-container')[0]
      if x && (x=x.text.gsub(',','')) =~ /\nConfirmed Cases\n([^\n]+)\n/
        h[:positive] = string_to_i($1)
        break
      elsif sec == 0
        @errors << 'missing positive'
        break
      end
    end
    # TODO counties is available in x
    # age in root page
    h
  end

  def parse_id(h)
    @driver.navigate.to @url
    @s = @driver.find_elements(class: 'wp-block-column')[0].text.gsub(',','').gsub(/\s+/,' ')
    if (x=(@s =~ /Public Health District County Cases Deaths/)) &&
       @s[x..-1] =~ / TOTAL\*? ([0-9]+) ([0-9]+) /
      h[:positive] = string_to_i($1)
      h[:deaths] = string_to_i($2)
    else
      @errors << 'missing cases and deaths'
    end
    if @s =~ /Number of people tested through the Idaho Bureau of Laboratories\*? ([0-9]+)/
      h[:tested] = string_to_i($1)
    else
      @errors << 'missing tested'
    end
    if @s =~ /Number of people tested through commercial laboratories\*?\*? ([0-9]+)/
      h[:tested] = 0 unless h[:tested]
      h[:tested] += string_to_i($1)
    else
      @errors << 'missing tested'
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
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Deaths/}.first
      h[:deaths] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing deaths'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Total Persons Tested/i}.first
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
    if @s =~ /<iframe[^>]+src=\"https:\/\/arcg\.is([^"]+)/
      @url = 'https://arcg.is' + $1
    else
      @errors << 'missing url'
      return h
    end
    @driver.navigate.to @url
    sec = SEC/2
    loop do
      sec -= 1
      puts 'sleeping'
      sleep 1
      @s = @driver.find_elements(class: 'claro')[0].text
      rows = @s.split("\n")
      if @s =~ /Data as of ([^\n]+)\n/
        h[:date] = $1
        break
      elsif sec == 0
        @warnings << 'missing date'
      end
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
    sec = SEC
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
    byebug unless @auto_flag
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
    # no death data
    h
  end

  def parse_la(h)
    @driver.navigate.to @url
    if @driver.page_source =~ /src="https:\/\/www.arcgis.com([^"]+)/
      @driver.navigate.to('https://www.arcgis.com' + $1)
    else
      @errors << 'link failed'
      return h
    end
    sec = SEC/2
    loop do
      sec -= 1
      puts 'sleeping' 
      sleep 1
      @s = @driver.find_elements(class: 'layout-reference')[0].text
      if @s =~ /\nData updated:([^\n]+)\n/
        h[:date] = $1.strip
      end
      if @s =~ /Information\n([^\n]+)\nCases Reported\*?\n([^\n]+)\nDeaths Reported\nTests Completed\n([^\n]+)\nby State Lab\nTests Reported to State\n([^\n]+)\n/
        h[:tested] = string_to_i($3) + string_to_i($4)
        h[:positive] = string_to_i($1)
        h[:deaths] = string_to_i($2)
        break
      elsif sec == 0
        @errors << 'parse failed'
        break
      end
    end # loop
    unless h[:date]
      @warnings << 'missing date'
    end
    h
  end

  # TODO download pdf
  def parse_ma(h)
    @driver.navigate.to @url
    sec = SEC/3
    loop do
      @s = @driver.find_elements(class: 'page-content')[0].text
      if @s =~ /\nConfirmed cases of COVID-19 ([^\n]+)\n/
        h[:positive] = string_to_i($1)
        break
      elsif sec == 0
        @errors << 'missing positive'
        break
      end
      sec -= 1
      puts 'sleeping'
      sleep 1
    end
    puts "pdf? manual entry of tested from pdf"
    h[:tested] = 2666 + 940 + 485
    byebug unless @auto_flag
    # no death data
    h
  end # parse_ma

  def parse_md(h)
    # TODO county, age
    @driver.navigate.to @url
    sec = SEC
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
    if (@driver.find_elements(class: 'container').map {|i| i.text}.select {|i| i=~/\nNumber of Deaths:([^\n]+)\n/}[0] =~ /\nNumber of Deaths:([^\n]+)\n/)
      h[:deaths] = $1.to_i
    else
      @errors << "missing deaths"
    end
    h
  end

  def parse_me(h)
    #@driver.navigate.to @url
    #byebug
    cols = @doc.css('table').map {|i| i.text}.select {|i| i=~/Confirmed Cases/}.first.split("\n").map {|i| i.strip}.select {|i| i.size > 0}
    if cols.size == 8
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Confirmed Cases/}.first
      h[:positive] = string_to_i(cols[x[1]+3])
    else
      @errors << 'missing positive'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Presumptive Positive Cases/}.first
      h[:positive] = 0 unless h[:positive]
      h[:positive] += string_to_i(cols[x[1]+3])
    else
      @warnings << 'missing positive 2'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Negative Tests/}.first
      h[:negative] = string_to_i(cols[x[1]+3])
    else
      @errors << 'missing negative'
    end
    elsif cols.size == 6
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Confirmed Cases/}.first
      h[:positive] = string_to_i(cols[x[1]+2])
    else
      @errors << 'missing positive'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Negative Tests/}.first
      h[:negative] = string_to_i(cols[x[1]+2])
    else
      @errors << 'missing negative'
    end
    end
    if x = cols.select {|i| i=~/^Updated: (.*)/}.first
      x=~/^Updated: (.*)/
      h[:date] = $1
    else
      @errors << 'missing date'
    end
    # counties
    # demographics
    # no death data
    h
  end

  def parse_mi(h)
    # TODO county, sex, age, hospitalization
    if @s =~ /href='([^']+)'>[^S<]+See Cumulative Data</
      @url = 'https://www.michigan.gov' + $1
    else
      @errors << 'missing url'
      return h
    end
    @driver.navigate.to @url
    if @s =~ /Updated COVID-19 reported data has been delayed and will be displayed as soon as available/
      @warnings << 'MI data being prepared'
      return h
    end
    cols = @driver.find_elements(class: 'fullContent')[0].text.gsub(',','').split("\n").map {|i| i.strip}.select {|i| i.size>0}

    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Total$/}.first
      h[:positive] = string_to_i(cols[x[1]+1])
      if cols.include?('County Cases Deaths')
        h[:deaths] = string_to_i(cols[x[1]+2])
      else
        @errors << 'missing deaths'
      end
      cols = cols[x[1]+1..-1]
    else
      @errors << 'missing positive'
    end
    if x = cols.select {|v,i| v=~/^Total /}.first
      h[:tested] = string_to_i(x.split.last)
    else
      @warnings << 'missing tested'
    end
    h
  end

  def parse_mn(h)
    @driver.navigate.to @url
    sec = SEC
    cols = []
    loop do
      begin
        cols = @driver.find_elements(id: 'body')[0].text.gsub(',','').split("\n").map {|i| i.strip}.select {|i| i.size > 0}
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
    if (x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Positive: /}.first) &&
      x[0] =~ /^Positive: ([0-9]+)/
      h[:positive] = string_to_i($1)
    else
      @errors << 'missing positive'
    end
    if (x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Deaths: /}.first) &&
      x[0] =~ /^Deaths: ([0-9]+)/
      h[:deaths] = string_to_i($1)
    else
      @errors << 'missing deaths'
    end
    h
  end  

  def parse_mo(h)
    # TODO click to get county
    #@driver.navigate.to @url
    tables = @doc.css('table').map {|i| i.text.gsub(',','')}
    cols = tables.select {|i| i=~/Deaths/}[0].split("\n").map {|i| i.strip}.select {|i| i.size > 0}
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Deaths/}.first
      h[:deaths] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing deaths'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Positive/}.first
      h[:positive] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing positive'
    end
    h
  end

  def parse_ms(h)
    @driver.navigate.to @url
# TODO get counties
    if (s=@driver.find_elements(class: 'rightColumn').map {|i| i.text}.select {|i| i=~/All Mississippi cases to date/}.first) && s.gsub(',','')=~/Total ([0-9]+) ([0-9]+)/
      h[:positive] = string_to_i($1)
      h[:deaths] = string_to_i($2)
    else
      @errors << 'missing positive and deaths'
    end
    s = @doc.css('body').text.gsub(',','')
    if s =~ /Total individuals tested for COVID-19: ([0-9]+)[^0-9]/i
      h[:tested] = string_to_i($1)
    else
      @errors << 'missing tested'
    end
    # counties in a nice table
    h
  end

  def parse_mt(h)
    @driver.navigate.to @url
    if @s =~ /<a href="https:\/\/montana\.maps\.arcgis\.com([^"]+)"/
      @url = 'https://montana.maps.arcgis.com' + $1
    else
      @errors << 'map url not found'
      return h
    end
    @driver.navigate.to @url
    sec = SEC/3
    loop do
      if @driver.page_source =~ /src=\"https:\/\/montana\.maps\.arcgis\.com\/apps\/opsdashboard([^"]+)"/
        @url = 'https://montana.maps.arcgis.com/apps/opsdashboard' + $1
        break
      elsif sec == 0
        @errors << 'map url2 not found'
        return h
      end
      sec -= 1
      puts 'sleeping'
      sleep 1
    end
    @driver.navigate.to @url
    sec = SEC/3
    loop do
      @s = @driver.find_elements(class: 'layout-reference')[0].text
      if @s =~ /Total Cases\n([^\n]+)\nLast update/
        h[:positive] = string_to_i($1)
        break
      elsif sec == 0
        @errors << 'missing positive'
        return h
      end
      sec -= 1
      puts 'sleeping' 
      sleep 1
    end
=begin
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/Persons with negative results/}.first
      h[:negative] = string_to_i(cols[x[1]+1])
    else
      @warnings << 'missing negative'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/Persons tested for COVID-19 by MTPHL\*/i}.first
      h[:tested] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing tested'
    end
=end
    h
  end  

  def parse_nc(h)
    @driver.navigate.to @url
    sec = SEC
    cols = []
    loop do
      begin
        cols = @driver.find_elements(class: 'content').map {|i| i.text}.select {|i| i=~/NC Cases/i}.last.split("\n").map{|i| i.strip}.select{|i| i.size>0}
        byebug if cols.size != 13 && !@auto_flag
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
    if @auto_flag
      puts 'skipping ND'
      h[:skip] = true
      return h
    end
    puts "image file for ND"
    h[:tested] = 1182
    h[:positive] = 28
    h[:negative] = 1154
    h[:pending] = 0
    h[:deaths] = 0 # TODO
    @driver.navigate.to @url
    byebug 
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
    if @s =~ />Cases that tested negative – ([^<]+)</
      h[:negative] = $1.to_i
      h[:tested] += h[:negative]
    else
      @errors << 'missing negative'
    end
    # no death data
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
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/Number of Persons with Test Pending/}.first
      h[:pending] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing pending'
    end
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
    # no death data
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
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/Negative/}.first
      h[:negative] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing negative'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^PUI pending/i}.first
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
    sec = SEC/3
    cols = []
    loop do
      begin
        cols = @driver.find_elements(class: "et_pb_text_inner").map {|i| i.text}.select {|i| i=~/COVID-19 Test Results in N/}[0].split("\n")
        @s = @driver.find_elements(class: "et_pb_text_inner").map {|i| i.text}.select {|i| i=~/COVID-19 Test Results in N/}[0]
        break
      rescue => e
        if sec == 0
          @errors << 'failed to parse table'
          return h
        end
        sec -= 1
        puts 'sleeping'
        sleep 1
      end
    end # loop
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
    # no death data
    h
  end

  def parse_nv(h)
    @driver.navigate.to(@url) rescue nil
    if @s =~ /"https:\/\/app\.powerbigov([^"]+)"/
      @url = 'https://app.powerbigov' + $1
    else
      @errors << 'bi url not found'
      return h
    end
    @driver.navigate.to(@url)
    @s = ''
    sec = SEC * 2
    loop do
      puts 'sleeping'
      sleep 1
      sec -= 1
      if sec == 0
        @errors << 'failed to load'
        return h
      end
      x = @driver.find_elements(class: 'landingController')[0]
      @s = x.text.gsub(',','') if x
      if (@s =~ /\n([0-9]+)Deaths Statewide\n/) && (@s =~ /\n([0-9]+)People Tested\n/) && (@s =~ /All\n([0-9]+)Negative\n([0-9]+)Positive\nResult/)
        h[:negative] = string_to_i($1)
        h[:positive] = string_to_i($2)
        @s =~ /\n([0-9]+)People Tested\n/
        h[:tested] = string_to_i($1)
        @s =~ /\n([0-9]+)Deaths Statewide\n/
        h[:deaths] = string_to_i($1)
        return h
      end
      byebug if @s.size > 1000 && !@auto_flag
      nil
    end    
    h
  end

  def parse_ny(h)
    @driver.navigate.to @url
    puts "death manual"
    h[:deaths] = 43 # from nyc report TODO
    byebug unless @auto_flag
    rows = @doc.css('table')[0].text.gsub(',','').split("\n").map {|i| i.strip}.select {|i| i.size>0}
    if rows[-2] == "Total Number of Positive Cases"
      h[:positive] = rows[-1].to_i
    else
      @errors << "missing positive"
    end
    # TOOD death data
    h
  end

  def parse_oh(h)
    @driver.navigate.to @url
    sec = SEC/3
    cols = []
    loop do
      begin
        cols = @driver.find_elements(class: 'odh-ads__container')[0].text.split("\n").map {|i| i.strip}.select {|i| i.size > 0}
        break
      rescue => e
        if sec == 0
          @errors << 'failed to parse table'
          return h
        end
        sec -= 1
        puts 'sleeping'
        sleep 1
      end
    end # loop
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Confirmed Cases/}.first
      h[:positive] = string_to_i(cols[x[1]-1])
    else
      @errors << 'missing positive'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Number of Deaths/}.first
      h[:deaths] = string_to_i(cols[x[1]-1])
    else
      @errors << 'missing deaths'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Number of Hospitalizations in Ohio/}.first
      h[:hospitalized] = string_to_i(cols[x[1]-1])
    else
      @errors << 'missing hospitalized'
    end
    # counties availble
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
      @errors << 'missing positive 2'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/Deaths/}.first
      h[:deaths] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing deaths'
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
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Hospitalized/}.first
      h[:hospitalized] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing hospitalized'
    end
    h
  end  

  def parse_or(h)
    @driver.navigate.to @url
    sec = SEC/3
    cols = []
    loop do
      begin
        cols = @driver.find_elements(class: 'card-body').map {|i| i.text.gsub(',','')}.select {|i| i=~/Oregon Test Results as of /}.first.split("\n")
        break
      rescue => e
        if sec == 0
          @errors << 'parse failed'
          return h
        end
        sec -= 1
        puts 'sleeping'
        sleep 1
      end
    end # loop
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
    @driver.find_elements(class: 'prefix-overlay-close').first.click
    x = @driver.find_elements(class: 'btn').map {|i| [i, i.text]}.select {|i,j| j=~/Demographic Information/}.first
    x.first.click
    cols = @driver.find_elements(class: 'card-body').map {|i| i.text.gsub(',','')}.select {|i| i=~/Deaths/}.first.split("\n")
    if (x = cols.select {|i| i=~/^Total ([0-9,]+) ([0-9,]+)/}.first) &&
      x =~ /^Total ([0-9,]+) ([0-9,]+)/
      h[:deaths] = string_to_i($2)
    else
      @errors << 'missing deaths'
    end
    # counties
    # hospitalized
    h
  end  

  def parse_pa(h)
    @driver.navigate.to @url
    if s = @driver.find_elements(class: 'ms-rteTable-default')[0]
      s = s.text.gsub(',','')
    else
      @errors << 'parse failed'
      byebug unless @auto_flag
      return h
    end
    if s =~ /Negative\sPositive\sDeaths\s([0-9]+)\s([0-9]+)\s([0-9]+)/
      h[:negative] = string_to_i($1)
      h[:positive] = string_to_i($2)
      h[:deaths] = string_to_i($3)
    else
      @errors << 'missing pos neg deaths'
    end
    h[:county_positive] = []
    cols = @driver.find_elements(class: 'ms-rteTable-default')[1].text.gsub(',','').gsub(/\s+/,' ').split
    if cols[2] == 'Deaths'
      cols = cols[3..-1]
      i = 0
      county = ''
      while cols.size > 0
        w = cols.shift
        if w =~/^[0-9]+$/
          if i == 0
            @errors << 'county table parse error, expecting county, not number'
            break
          elsif i == 1
            h[:county_positive] << [county, string_to_i(w)]
            i = 2
          else 
            # county death
            #h[:deaths] += string_to_i(w)
            i = 0
          end
        else
          if i == 0 || i == 2
            county = w
            i = 1
          else
            @errors << 'count table parse error2, expecting number, not county'
            break
          end
        end
      end
    else
      @errors << "missing county deaths"
    end
    # counties
    h
  end

  def parse_ri(h)
    @driver.navigate.to @url
    sec = SEC
    loop do
      begin
        break if (@s = @driver.find_elements(class: 'panel')[0].text.gsub(',','')) =~ /Number of Rhode Island COVID-19 positive \(including/
      rescue => e
        sec -= 1
        if sec == 0
          @errors << 'failed to parse'
          return h
        end
        puts 'sleeping'
        sleep(1)
      end
    end
    cols = @s.split("\n")
    if (x = cols.select {|v,i| v=~/^Number of Rhode Island COVID-19 positive \(including/}.first)
      h[:positive] = string_to_i(x.strip.split.last)
    else
      @errors << 'missing pos'
    end
    if (x = cols.select {|v,i| v=~/^Number of people who had negative test results/}.first)
      h[:negative] = string_to_i(x.strip.split.last)
    else
      @errors << 'missing neg'
    end
    if (x = cols.select {|v,i| v=~/^Number of people for whom tests are pending/}.first)
      h[:pending] = string_to_i(x.strip.split.last)
    else
      @errors << 'missing pending'
    end
    # no death data
    h
  end

  def parse_sc(h)
    @driver.navigate.to @url
    sec = SEC
    rows = []
    loop do
      begin
        rows = @driver.find_elements(id: 'dmtable')[0].text.gsub(',','').split("\n").map {|i| i.strip}.select {|i| i.size > 0}
        raise if rows.size == 0
        break
      rescue => e
        sec -= 1
        if sec == 0
          @errors << 'failed to parse'
          return h
        end
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
    if @driver.page_source =~ /"([^"]+)arcgis\.com([^"]+)"/
      @driver.navigate.to($1 + 'arcgis.com' + $2)
      sec = SEC
      loop do
        if @driver.page_source =~ /src=\"https:\/\/arcg.is([^"]+)/
          @driver.navigate.to('https://arcg.is' + $1)
          @s = @driver.find_elements(class: 'dashboard-page').first.text
          if @s =~ /Deaths in Individuals with COVID-19 infection\n([^\n]+)\n/
            h[:deaths] = string_to_i($1)
          else
            @errors << 'missing deaths inner'
          end
# TODO get counties
          break
        end
        sec -= 1
        break if sec == 0
        puts 'sleeping'
        sleep 1
      end
    else
      @errors << 'missing iframe'
    end
    h
  end

  def parse_sd(h)
    rows = @doc.css('table').map {|i| i.text.gsub(',','').gsub(/\s+/,' ')}
    if (x=rows.select {|i| i=~/Positive\*? ([0-9]+) Negative ([0-9]+) Pending ([0-9]+) /}.first) &&
      x =~ /Positive\*? ([0-9]+) Negative ([0-9]+) Pending ([0-9]+) /
      h[:positive] = string_to_i($1)
      h[:negative] = string_to_i($2)
      h[:pending] = string_to_i($3)
      h[:tested] = h[:pending] + h[:positive] + h[:negative]
    else
      @errors << "missing tests"
    end
    if (x=rows.select {|i| i=~/Deaths ([0-9]+) /}.first) &&
      x =~ /Deaths ([0-9]+) /
      h[:deaths] = string_to_i($1)
    else
      @errors << "missing tests"
    end
    h
  end  

  def parse_tn(h)
    #@driver.navigate.to @url
    #byebug
    cols = @doc.css('table')[0].text.split("\n").map {|i| i.strip}.select {|i| i.size > 0}
    if cols.size != 15
      byebug unless @auto_flag
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
    # no death data
    h
  end

  def parse_tx(h)
    #@driver.navigate.to @url
    #byebug
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
    @s = @driver.find_elements(class: 'dashboard-page-wrapper').first.text
    if @s =~ /Report Date: ([^\n]+)\n([^\n]+)\nCOVID-19 Cases\n([^\n]+)*\nReported People Tested\n([^\n]+)\nCOVID-19 Deaths\n/
      h[:date] = $1
      h[:positive] = string_to_i($2)
      h[:tested] = string_to_i($3)
      h[:deaths] = string_to_i($4)
    else
      @errors << 'missing positive'
    end
    h
  end # parse_ut

  def parse_va(h)
    if @auto_flag
      puts "skipping VA"
      h[:skip] = true
      return h
    end
    @driver.navigate.to @url
    if @driver.page_source =~ /<iframe src=\"https:\/\/public\.tableau\.com([^"]+)"/
      @url = 'https://public.tableau.com' + $1
    else
      @errors << 'missing tableau url'
      return h
    end 
    @driver.navigate.to @url
    puts 'need to manually get numbers from tableau'
    h[:tested] = 2790
    h[:positive] = 152
    h[:negative]
    h[:pending]
    h[:deaths] = 2 # TODO
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
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/Deaths/}.first
      h[:deaths] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing deaths'
    end
    h
  end

  def parse_wa(h)
    @driver.navigate.to @url
    sec = SEC
    cols = []
    loop do
      begin
        cols = @driver.find_elements(class: 'contentmain')[0].text.split("\n").map {|i| i.strip}.select {|i| i.size > 0}
      rescue
        sec -= 1
        puts 'sleeping'
        sleep 1
      end
      if sec == 0
        @errors << 'cols fail'
        break
      end
      break if cols.size > 0
    end
    x = cols.select {|i| i=~/^Negative\s+([^\s+]+)/}
    if x.size == 1 && x[0] =~ /^Negative\s+([^\s+]+)/
      h[:negative] = string_to_i($1)
    else
      @errors << 'negative'
    end
    if (x=cols.select {|i| i=~/^Total / && i.split.size==3}).size > 0 && (x=x[0].split) && x[0]=='Total'
      h[:positive] = string_to_i(x[1])
      h[:deaths] = string_to_i(x[2])
    else
      @errors << 'missing deaths'
    end
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
    if @s =~ /\nNegative ([0-9]+)\nPositive ([0-9]+)\nDeaths ([0-9]+)\n/
      h[:positive] = string_to_i($2)
      h[:negative] = string_to_i($1)
      h[:deaths] = string_to_i($3)
    else
      @errors << "missing cases"
    end
    h
  end # parse_wi

  def parse_wv(h)
    @driver.navigate.to @url
    sec = SEC/5
    cols = []
    loop do
      begin
        cols = @driver.find_elements(class: 'bluebkg')[0].text.split("\n").map {|i| i.strip}.select {|i| i.size > 0}
        break
      rescue => e
        if sec == 0
          @errors << 'failed to parse table'
          return h
        end
        sec -= 1
        puts 'sleeping'
        sleep 1
      end
    end # loop
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
    if @s =~ /Tests reported by commercial labs: ([^<]+)</
      h[:tested] += string_to_i($1)
    else
      @errors << "missing tested 3"
    end
    # no death data
    h
  end

  ######################################

  # look for a word on the webpage
  # TODO birth is hard coded
  def search_term(word='death')
    doc_text = @doc.text.encode('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: '')
    if (i = (doc_text =~ /#{word}/i)) && !(doc_text =~ /birth/i)
      puts "found #{word} in #{@st}"
      puts doc_text[(i-30)..(i+30)]
      return true
    end
    @driver.navigate.to @url
    if (i = (@driver.page_source =~ /#{word}/i)) && !(doc_text =~ /birth/i)
      puts "found #{word} in #{@st}"
      puts @driver.page_source[(i-30)..(i+30)]
      return true
    end
    false
  end

  # convert a string to an int
  def string_to_i(s)
    return s if s.class == Integer
    return 0 if s == "--"
    if s =~ /Appx\. (.*)/
      s = $1
    elsif s =~ /~(.*)/
      s = $1
    elsif s =~ /App/
      byebug unless @auto_flag
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
          puts "Please fix. Invalid number string: #{s}"
          temp = nil
          byebug unless @auto_flag
          return temp
        end
      end
    end
  end

  def initialize
    @driver = Selenium::WebDriver.for :firefox
    @path = 'data/'
    # load previous numbers
    lines = open('all.csv').readlines.map {|i| i.split("\t")}
    # previous state stats
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
    puts "method_missing called on state: #{@st}"
    if @auto_flag
      h[:skip] = true
      return h
    end
    @driver.navigate.to @url
    byebug
    h
  end

  # main execution loop
  # 
  # default is to run all states in automatic mode
  # or you can specifiy the list of states to run
  # if auto_flag is false, will prompt you for certain states
  #
  def run(crawl_list = [], auto_flag = true, debug_page_flag = false)
    @auto_flag = auto_flag
    h_all = []
    errors_crawl = []
    warnings_crawl = []
    skipped_crawl = []
    tested   = {:all => 0}
    positive = {:all => 0}
    deaths   = {:all => 0}

    pui      = {:all => 0}
    #pui_cumulative
    #quarantined

    skip_flag = OFFSET
    filetime = Time.now.to_s[0..18].gsub(' ', '-')
    filetime = filetime.gsub(':', '.')

    for @st, @url in (open('states.csv').readlines.map {|i| i.strip.split("\t")}.map {|st, url| [st.downcase, url]})
      if crawl_list.size > 0
        next unless crawl_list.include?(@st)
      end
      puts "CRAWLING: #{@st}"

      skip_flag = false if @st == OFFSET
      next if skip_flag
      next if SKIP_LIST.include?(@st)
      # `mkdir -p #{@path}#{@st}`
      unless Dir.exist?("#{@path}#{@st}")
        unless Dir.exist?("#{@path}")
          Dir.mkdir("#{@path}")
        end
        Dir.mkdir("#{@path}#{@st}")
      end 
    
      @s = `curl -s #{@url}`
      @doc = Nokogiri::HTML(@s)
      @errors = []
      @warnings = []
      h = {:ts => Time.now, :st => @st, :source_urls => [@url], :source_texts => []}
      begin
        h = send("parse_#{@st}", h)
      rescue => e
        @errors << "parse_#{@st} crashed: #{e.inspect}"
      end

      if h[:skip]
        skipped_crawl << @st
      else
        open("#{@path}#{@st}/#{filetime}", 'w') {|f| f.puts @s} # @s might be modified in parse

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
          puts "only deaths changed for #{@st}"
          puts "old h: #{@h_prev[@st]}"
          puts "new h: #{h}"
          unless @auto_flag
            @driver.navigate.to(@url) rescue nil
            byebug
            puts
          end
        elsif @h_prev[@st][:positive] == h[:positive]
          if h[:tested] 
            puts "tested different, positives same for #{@st}"
            puts "old h: #{@h_prev[@st]}"
            puts "new h: #{h}"
            unless @auto_flag
              @driver.navigate.to(@url) rescue nil
              byebug
              puts
            end
          else
            # missing tested in new
          end
        elsif !h[:positive]
          puts "missing positive for #{@st}"
          puts "old h: #{@h_prev[@st]}"
          puts "new h: #{h}"
          unless @auto_flag
            @driver.navigate.to(@url) rescue nil
            byebug
            puts
          end
        elsif h[:positive] < @h_prev[@st][:positive]
          puts "positive decreased for #{@st}"
          puts "old h: #{@h_prev[@st]}"
          puts "new h: #{h}"
          unless @auto_flag
            @driver.navigate.to(@url) rescue nil
            byebug
            puts 
          end
        elsif ((h[:tested] && tested_new > h[:tested]) || count == 3 || (count == 4 && (h[:tested] != (h[:positive] + h[:negative] + h[:pending])))) && !h[:skip]
          puts "please double check stats, for #{@st}:"
          puts "old h: #{@h_prev[@st]}"
          puts "new h: #{h}"
          unless @auto_flag
            @driver.navigate.to(@url) rescue nil
            byebug
            puts
          end
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

        warnings_crawl << { @st => @warnings } if @warnings.size > 0

        if @errors.size != 0 && !h[:skip]
          errors_crawl << { @st => @errors }
          puts
          puts "ERROR in #{@st}: #{@errors.inspect}"
          puts "new h: #{h}"
          unless @auto_flag
            @driver.navigate.to @url
            byebug
            puts
          end
        elsif debug_page_flag && !@auto_flag 
          puts
          puts "DEBUG PAGE FLAG"
          puts @st
          puts h.inspect
          puts
          puts({:tested => h[:tested], :pos => h[:positive], :neg => h[:negative], :pending => h[:pending]}.inspect)
          #@driver.navigate.to @url
          byebug 
          puts
        end

        unless h[:deaths]
          x = nil
          begin
            x = search_term('death')
          rescue => e
            puts "search_term failed: #{e.inspect}"
          end
          if x
            puts h.inspect
            byebug unless @auto_flag
            puts
          end
        end

        h_all << h  
        # save parsed h
        open("#{@path}#{@st}.log",'a') {|f| f.puts h.inspect} if h && h.size > 0 && !(h[:skip])

        puts ["Update for #{@st}", "new: [#{h[:tested]}, #{h[:positive]}, #{h[:deaths]}]", 
          "old: [#{@h_prev[@st][:tested]}, #{@h_prev[@st][:positive]}, #{@h_prev[@st][:deaths]}]"].join("\t")

      end # unless h[:skip]
    end # states @st loop

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
    puts "#{errors_crawl.size} errors:"
    puts errors_crawl.inspect
    puts
    puts "#{warnings_crawl.size} warnings:"
    puts warnings_crawl.inspect
    puts
    puts "#{skipped_crawl.size} skipped:"
    puts skipped_crawl.inspect
    puts
    
    puts "done."
    errors_crawl.map {|i| i.keys.first}
  end # end run

end # Crawler class
