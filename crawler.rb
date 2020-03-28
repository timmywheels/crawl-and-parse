require 'byebug'
require 'nokogiri'
require 'selenium-webdriver'
require 'pdf-reader'

# not automatic:
# ['ak', "az", "ct", 'hi', 'ma', "nd", 'ny', "va"] 
# pdf for more data: ct, ma, ny
# image: ak

# counties done: ny

# page missing data: de, ia, ky, md, me, mi, mo, mt, ne, oh, ri

SEC = 60 # seconds to wait for page to load
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
    crawl_page
    cols = @doc.css('table').map {|i| i.text.gsub(',','')}.select {|i| i=~/Travel\-Related/}.first.split("\n").map {|i| i.strip}.select {|i| i.size>0}
    if cols[-6] == " TOTAL"
      h[:positive] = string_to_i(cols[-1])
    else
      @errors << 'missing positive'
    end
    if @driver.find_elements(id: 'content-wrapper')[0].text.gsub(',','') =~ /Cumulative number of deaths to date:([^\n]+)\n/
      h[:deaths] = string_to_i($1)
    else
      @errors << 'missing deaths'
    end
    puts 'AK: tested data in image?'

    `curl http://dhss.alaska.gov/dph/Epi/id/PublishingImages/COVID-19/COVID-1_AKtesting_cumulative.png > #{@path}#{@st}/#{@filetime}_1.png`
    h[:tested] = 1225+1163 # from image! save image?
    unless @auto_flag
      `open #{@path}#{@st}/#{@filetime}_1.png`
      byebug 
    end
    # Cumulative number of cases hospitalized to date:  0
    # positive by region available
    # no death data
    # TODO TESTED manual
    h
  end

  def parse_al(h)
    crawl_page
    url = @s.scan( /[^'"]+alpublichealth.maps.arcgis.com[^'"]+/ )[0]
    raise unless url
    crawl_page url
    sec = SEC
    loop do
      t = @driver.find_elements(class: 'dashboard-page')[0]
      if t && (@s=t.text.gsub(',','')) =~ /CONFIRMED\n([\d]+)\nTOTAL TESTED\*?\n([\d]+)\nDEATHS\s?\n([\d]+)/
        h[:tested] = string_to_i($2)
    	h[:deaths] = string_to_i($3)
        h[:positive] = string_to_i($1)
        break
      end
      sec -= 1
      if sec == 0
        @errors << 'parse failed'
        break
      end
      puts 'sleeping'
      sleep 1
    end
    # counties available
    h
  end

  def parse_ar(h)
    crawl_page
    @url = @driver.page_source.scan(/http[^'"]+maps\.arcgis\.com[^'"]+/)[0]
    unless @url
      @errors << 'url missing'
      return h
    end
    crawl_page
    sec = SEC
    loop do
      flag = false
      @s=@driver.find_elements(class: 'dashboard-page')[0].text
      t = @s.scan(/Arkansas Totals\nCumulative Cases\n([^\n]+)\n/)
      if t.size > 0
        h[:positive] = string_to_i(t[0][0])
      else
        flag = true
      end
      t = @s.scan(/\nTotal Tested for COVID-19\n([^\n]+)/)
      if t.size > 0
        h[:tested] = string_to_i(t[0][0])
      else
        flag = true
      end 
      t = @s.scan(/\nDeaths\n([^\n]+)/)
      if t.size == 2
        h[:deaths] = string_to_i(t[0][0])
      else
        flag = true
      end
      if flag
        puts 'sleeping' 
        sec -= 1
        sleep 1
        if sec == 0
          @errors << 'parse failed'
          return h
        end
      else
        break 
      end
    end
    h
  end

  def parse_az(h)
    # TODO use https://www.azdhs.gov/preparedness/epidemiology-disease-control/infectious-disease-epidemiology/index.php#novel-coronavirus-home
=begin
    @driver.navigate.to(@url) 
    unless @url = @driver.page_source.scan(/http[^'"]+tableau\.azdhs\.gov\/views[^'"]+/)[0]
      @errors << 'missing url'
      return h
    end
=end
    crawl_page
    if @auto_flag
      puts "skipping AZ"
      h[:skip] = true
      return h
    end
    `rm /Users/danny/Downloads/Cases_crosstab.csv`
    `rm /Users/danny/Downloads/Testing_crosstab.csv`
    sleep(3)
    @driver.find_elements(class: "tabCanvas")[0].click
    @driver.find_elements(class: "download")[0].click
    x = @driver.find_elements(class: "tab-downloadDialog")[0]

#x.find_elements(:css, "*")[4].click
#byebug
#@driver.find_elements(class: "tab-pdf-dialog-buttons")[0].click

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
  end

  def parse_ca(h)
    crawl_page
    sec = SEC/5
    loop do
      @s = @driver.find_elements(id: 's4-workspace').first.text.gsub(/\s+/,' ')
      if @s =~ /there are a total of (.*) positive cases and (.*) deaths /
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
    urls = @driver.page_source.scan(/Programs\/OPA\/Pages\/NR[^"']+/).map {|i| 'https://www.cdph.ca.gov/' + i} #.sort.reverse
    crawl_page urls.shift
    if (x=@driver.find_element(id: 'MainContent')) && x.text =~ /pproximately ([0-9,]+) tests had been conducted in California/
      h[:tested] = string_to_i($1)
    else
      @errors << 'missing tested'
    end
    # TODO source is 2 urls
    h
  end

  def parse_co(h)
    crawl_page
    #byebug
    @s = @driver.find_elements(class: 'container').map {|i| i.text}.select {|i| i=~/Colorado Case Summary/}[0]
    if @s && @s.gsub!(',','') &&
      @s =~ /\n([0-9]+)[^0-9]?cases\*?\n([0-9]+)[^0-9]?hospitalized\n([0-9]+)[^0-9]?counties\n([0-9]+)[^0-9]?people tested\n([0-9]+)[^0-9]?deaths/
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
h[:tested]=8400
h[:positive]=1291
h[:deaths]=27
h[:hospitalized] = 173
h[:negative]
h[:pending]
    crawl_page
    if @s =~ /([^'"]+CTDPHCOVID19summary[^'"]+)/
      url = 'https://portal.ct.gov' + $1
      `curl #{url} -o #{@path}#{@st}/#{@filetime}_1.pdf`
      `open #{@path}#{@st}/#{@filetime}_1.pdf`
      puts 'manual entry from pdf' # TODO automate
      byebug unless @auto_flag
    else
      @errors << 'missing pdf'
    end
    h
  end

  def parse_dc(h)
    # TODO count calc may be off
    crawl_page
    @s = @driver.find_elements(id: 'page').first.text.gsub(',','').gsub(/\s+/,' ')
    if (x = @s.scan(/Number of PHL positives:\s?([0-9]+)[^0-9]/)).size > 0
      h[:positive] = x.map {|i| string_to_i(i.first)}.max
    else
      @errors << "positive missing"
    end
    if (x = @s.scan(/Number of commercial lab positives:\s?([0-9]+)[^0-9]/)).size > 0
      h[:positive] = 0 unless h[:positive]
      h[:positive] += x.map {|i| string_to_i(i.first)}.max
    else
      @errors << "positive2 missing"
    end
    if (x = @s.scan(/Number of people tested overall:\s?([0-9]+)[^0-9]/)).size > 0
      h[:tested] = x.map {|i| string_to_i(i.first)}.max
    else
      @errors << "tested missing"
    end
    if (x = @s.scan(/Number of PHL tests in progress:\s?([0-9]+)[^0-9]/)).size > 0
      h[:pending] = string_to_i(x[0][0])
    else
      @warnings << "pending missing"
    end
    if (x = @s.scan(/Number of deaths:\s?([0-9]+)[^0-9]/)).size > 0
      h[:deaths] = string_to_i(x[0][0])
    else
      @errors << "deaths missing"
    end
    h
  end

  def parse_de(h)
    crawl_page
    @s = @s.encode('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: '')
    if @s =~ /https:\/\/dshs.maps.arcgis.com([^"]+)"/
      crawl_page('https://dshs.maps.arcgis.com' + $1)
    else
      @errors << 'dashboard url not found'
      return h
    end
    sec = SEC/2
    loop do
      @s = @driver.find_elements(class: 'layout-reference')[0].text
      if @s =~ /Total Cases\n([^\n]+)/ #\nTotal Deaths\n([^\n]+)\n/
        h[:positive] = string_to_i($1)
        #h[:deaths] = string_to_i($2)
        break
      end
      sec -= 1
      if sec == 0
        @errors << 'parse failed'
        return h
      end
      puts 'sleeping'
      sec -= 1
      sleep 1
    end
    @errors << 'DE took deaths off'
    # TODO tested, not available
    # TODO counties
    h
  end

  def parse_fl(h)
    crawl_page
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
      crawl_page url
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
        crawl_page url
        sec = SEC
        loop do
          begin
            @driver.find_elements(class: 'tab-title')[1].click
            s = @driver.find_elements(class: 'dashboard-page')[0].text
            if s =~ /\nTotal Tests\n([^\n]+)\n/
              h[:tested] = string_to_i($1)
              break
            end
          rescue
          end
          if s == 0
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
  end

  def parse_ga(h)
    crawl_page
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
    crawl_page
    s=@driver.find_element(id: 'main').text.gsub(',','')
    tables = @driver.find_elements(class: 'data_list').map {|i| i.text.gsub(',','')}
    if t=s.scan(/Total \(new\):\s([\d]+)/).first
      h[:positive] = string_to_i(t[0]) 
    elsif (t=tables.select {|i| i=~/Total cases/}.first) && t =~ /Total cases: ([\d]+)/
      h[:positive] = string_to_i($1)
    else
      @errors << 'missing positive'
    end
    if t=s.scan(/Total Deaths:\s([\d]+)/).first
      h[:deaths] = string_to_i(t[0])
    elsif (t=tables.select {|i| i=~/Hawaii deaths/}.first) && t =~ /Hawaii deaths: ([\d]+)/
      h[:deaths] = string_to_i($1)
    else
      @errors << 'missing deaths'
    end

    

    # county cases
    # hospitalized is in PR
    h[:tested] = 3862+322+263  # from PR
    # TODO tested 
    unless @auto_flag
      @driver.navigate.to 'https://health.hawaii.gov/news/covid-19-updates/'
      byebug 
    end
    h
  end

  def parse_ia(h)
    crawl_page
    t = @driver.page_source.scan(/there have been ([^\s]+) negative COVID-19 test results reported/)
    if t.size > 0
      h[:negative] = string_to_i(t[0][0])
    else
      @errors << 'missing negative'
    end
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
    crawl_page
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
    # TODO deaths tested
    h
  end

  def parse_id(h)
    crawl_page
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
    crawl_page
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
  end

  def parse_in(h)
    crawl_page
    if @s =~ /<iframe[^>]+src=\"https:\/\/arcg\.is([^"]+)/
      @url = 'https://arcg.is' + $1
    else
      @errors << 'missing url'
      return h
    end
    crawl_page
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
    crawl_page
    sec = SEC
    loop do
      if url = @driver.page_source.scan(/http[^'"]+arcg\.is[^'"]+/).first
        crawl_page url
        break
      end
      sec -= 1
      puts 'sleeping'
      sleep 1
      if sec == 0
        @errors << 'missing url'
        break
      end
    end
    sec = SEC
    loop do
      flag = true
      @s = @driver.find_elements(class: 'dashboard-page')[0].text
      t = @s.scan(/Total Cases\nPositive\*?\n([^\n]+)\n([^\n]+)\n([^\n]+)\nDeaths\n([^\n]+)/)
      if t.size == 1 && @s =~ /Total Negative:\n([^\n]+)\n/
        h[:negative] = string_to_i($1)
        h[:positive] = string_to_i(t[0][0])
        h[:deaths] = string_to_i(t[0][3])
        break
      end
      sec -= 1
      puts 'sleeping'
      sleep 1
      if sec == 0
        @errors << 'missing positive and deaths'
        break
      end
    end
    # TODO tested
    h
  end

  def parse_ky(h)
    crawl_page
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
    # TODO no death data
    h
  end

  def parse_la(h)
    crawl_page
    if @driver.page_source =~ /src="https:\/\/www.arcgis.com([^"]+)/
      crawl_page('https://www.arcgis.com' + $1)
    else
      @errors << 'link failed'
      return h
    end
    sec = SEC/2
    loop do
      sec -= 1
      puts 'sleeping' 
      sleep 1
      begin
        @s = @driver.find_elements(class: 'layout-reference')[0].text
      rescue
        @s = ''
      end
      if @s =~ /\nData updated:([^\n]+)\n/
        h[:date] = $1.strip
      end
      if @s =~ /Information\n([^\n]+)\nCases Reported\*?\n([^\n]+)\nDeaths Reported\nReported COVID-19 Patients in Hospitals\n([^\n]+)\n([^\s]+) of those on ventilators\nTests Completed\n([^\n]+)\nby State Lab\nCommercial Tests Completed\n([^\n]+)/
        h[:tested] = string_to_i($5) + string_to_i($6)
        h[:positive] = string_to_i($1)
        h[:deaths] = string_to_i($2)
        h[:hospitalized] = string_to_i($3)
        h[:on_ventilators] = string_to_i($4)
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
    # puts "h:"
    # puts h
    crawl_page
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
h[:deaths]=35
h[:tested]=29371
    if @driver.page_source =~ /([^'"]+covid-19-cases-in-massachusetts-as-of[^'"]+)/
      url = 'https://www.mass.gov' + $1
      `curl #{url} -o #{@path}#{@st}/#{@filetime}_1.pdf`
      `open #{@path}#{@st}/#{@filetime}_1.pdf`

      ###

      arr = []
      PDF::Reader.open(`#{@path}#{@st}/#{@filetime}_1.pdf`) do |reader|
        reader.pages.each do |page|
          byebug
          arr << page.text
          puts arr
        end
        puts arr
      end


      # sleep 3
      # @driver.find_element(:xpath, '//*[@id="download-ToolbarButton"]').click
      # @driver.find_element(:xpath, '//*[@id="DownloadDialog-Dialog-Body-Id"]/div/button[4]').click
      # sleep 3
      # @driver.find_element(:xpath, '//*[@id="PdfDialog-Dialog-Body-Id"]/div/div[2]/div[4]/button').click
      # sleep 5
      # reader = PDF::Reader.new(File.join(ENV['userprofile'], "Downloads", filename ))
      # result = reader.page(1).text

      ###

      # puts 'manual entry from pdf' # TODO automate
      # byebug unless @auto_flag
    else
      @errors << 'missing pdf'
    end 
    # TODO no death tested
    h
  end

  def parse_md(h)
    # TODO county, age
    crawl_page
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
    # TODO tested
    h
  end

  def parse_me(h)
    crawl_page
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
    # TODO no death data
    h
  end

  def parse_mi(h)
# TODO tests back
    # TODO county, sex, age, hospitalization
    crawl_page
    x = @driver.find_elements(class: 'btn').select {|i| i.text =~ /Cumulative Data/i}.first
    unless x
      @errors << 'button not found'
      return h
    end
    x.click
    if @s =~ /Updated COVID-19 reported data has been delayed and will be displayed as soon as available/
      @errors << 'MI data being prepared'
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
      @errors << 'missing tested'
    end
    # TODO tested no longer available
    h
  end

  def parse_mn(h)
    crawl_page
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
    if x = cols.select {|v,i| v=~/Approximate number of completed tests from the MDH /}.first
      h[:tested] = string_to_i(x.strip.split.last)
    else
      @errors << 'missing tested'
    end
    if x = cols.select {|v,i| v=~/Approximate number of completed tests from external/}.first
      h[:tested] = 0 unless h[:tested]
      h[:tested] += string_to_i(x.strip.split.last)
    else
      @errors << 'missing tested2'
    end
    if (x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/Total Positive: /i}.first) &&
      x[0] =~ /Total Positive: ([0-9]+)/i
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
    # TODO tested no longer available
    h
  end  

  def parse_mo(h)
    # TODO click to get county
    crawl_page
    @s.gsub!(',','')
    if @s =~ /Cases in Missouri: ([0-9]+)/
      h[:positive] = string_to_i($1)
    else
      @errors << 'missing positive'
    end
    if @s =~ /Total Deaths: ([0-9]+)/
      h[:deaths] = string_to_i($1)
    else
      @errors << 'missing deaths'
    end
    # TODO tested not available
    h
  end

  def parse_ms(h)
    crawl_page
# TODO get counties
    if (s=@driver.find_elements(id: 'msdhTotalCovid-19Cases')[0]) && 
      (s.text.gsub(',','') =~ /\nTotal\s([0-9]+)\s([0-9]+)/)
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
    crawl_page
    if @s =~ /<a href="https:\/\/montana\.maps\.arcgis\.com([^"]+)"/
      @url = 'https://montana.maps.arcgis.com' + $1
    else
      @errors << 'map url not found'
      return h
    end
    crawl_page
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
    crawl_page
    sec = SEC/3
    loop do
      @s = @driver.find_elements(class: 'layout-reference')[0].text
# County is available
      flag = false
      if @s =~ /Total Cases\n([^\n]+)\n/
        h[:positive] = string_to_i($1)
        sleep 2
      else
        flag = true
      end
      if @s =~ /Total Number of Tests Completed [\/0-9]+:([^\n]+)/
        h[:tested] = string_to_i($1)
      else
        #flag = true
      end
      if flag
        sec -= 1
        if sec == 0
          @errors << 'parse failed'
          return h
        end
        puts 'sleeping' 
        sleep 1
      else
        break
      end
    end
    # TODO deaths not available
    h
  end  

  def parse_nc(h)
    crawl_page
    sec = SEC
    cols = []
    loop do
      begin
        cols = @driver.find_elements(class: 'content').map {|i| i.text}.select {|i| i=~/NC Completed Tests/i}.last.split("\n").map{|i| i.strip}.select{|i| i.size>0}
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
      h[:positive] = string_to_i(cols[x[1]+4])
    else
      @errors << 'missing positive'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^NC Deaths/i}.first
      h[:deaths] = string_to_i(cols[x[1]+4])
    else
      @errors << 'missing deaths'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^NC Completed Tests/i}.first
      h[:tested] = string_to_i(cols[x[1]+4])
    else
      @errors << 'missing tested'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/Hospitalized/i}.first
      h[:hospitalized] = string_to_i(cols[x[1]+4])
    else
      @errors << 'missing hospitalized'
    end
    h
  end

  def parse_nd(h)
    crawl_page
    if @auto_flag
      puts 'skipping ND'
      h[:skip] = true
      return h
    end
    puts "image file for ND"
    h[:tested] = 2708
    h[:positive] = 68
    h[:negative] = 2640
    h[:hospitalized] = 16
    h[:pending] = 0
    h[:deaths] = 1 # TODO manual
    byebug 
    h
  end  

  def parse_ne(h)
    crawl_page
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
    # TODO no death data
    h
  end  

  def parse_nh(h)
    crawl_page
    #byebug
    cols = @doc.css('table')[0].text.split("\n").map {|i| i.strip}.select {|i| i.size > 0}
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/Number of Persons with covid/i}.first
      h[:positive] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing positive'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/Deaths Attributed to COVID/i}.first
      h[:deaths] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing deaths'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/Hospitalizations/i}.first
      h[:hospitalized] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing hospitalized'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/Persons with Test Pending /i}.first
      h[:pending] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing pending'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/Persons with Specimens Submitted/i}.first
      h[:tested] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing tested'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/Persons Being Monitored/i}.first
      h[:monitored] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing monitored'
    end
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/Persons Tested Negative/i}.first
      h[:negative] = string_to_i(cols[x[1]+1])
    else
      @errors << 'missing negative'
    end
    # TODO no death data
    h
  end

  def parse_nj(h)
    crawl_page
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
    url = 'https://covid19.nj.gov/'
    crawl_page url
    url = 'https://' + @driver.page_source.scan(/maps\.arcgis\.com\/apps\/opsdashboard\/index\.html[^'"]+/)[0]
    crawl_page url
    sec = SEC
    county_pos = 0
    loop do 
      cols = (@driver.find_element(class: 'dashboard-page').text.split("\n").map {|i| i.strip}) rescue []
      if cols.size > 0
        if (x=cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Bergen County/}.first) &&
          (y=cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/^Salem County/}.first)
          county_count = ((y[1]-x[1])/2+1)
          if county_count == 21
            h[:counties] = []
            county_pos = 0
            county_count.times do |i|
              h_county = {}
              j = i*2+x[1]
              h_county[:name] = cols[j]
              h_county[:positive] = string_to_i(cols[j+1].split("\s").first)
              county_pos += string_to_i(cols[j+1].split("\s").first)
              h[:counties] << h_county
            end
            break
          end    
        end
      end
      sec -= 1
      if sec == 0
        @errors << 'counties failed'
        break
      end
      puts 'sleeping'
      sleep 1
    end
    if h[:positive] != county_pos
      #@errors << 'county pos do not add up'
      # provisional pos are not counted
    end
    h
  end

  def parse_nm(h)
    crawl_page
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
    if x = cols.map.with_index {|v,i| [v,i]}.select {|v,i| v=~/COVID-Related Deaths in New Mexico/i}.first
      h[:deaths] = string_to_i(x[0].split.last)
    else
      @errors << 'missing deaths'
    end
    h
  end

  def parse_nv(h)
    crawl_page
    if @s =~ /"https:\/\/app\.powerbigov([^"]+)"/
      @url = 'https://app.powerbigov' + $1
    else
      @errors << 'bi url not found'
      return h
    end
    crawl_page
    @s = ''
    sec = SEC * 3
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
    crawl_page
    puts "death manual"
    h[:deaths] = 366 # from nyc report TODO
    rows = @doc.css('table')[0].text.gsub(',','').split("\n").map {|i| i.strip}.select {|i| i.size>0}
    county_pos = 0
    if rows[-2] == "Total Number of Positive Cases"
      h[:positive] = rows[-1].to_i
      county_count = ((rows.size-4)/2)
      if rows[1] == "Positive Cases" && county_count == 53
        h[:counties] = []
        county_count.times do |i|
          h_county = {}
          h_county[:name] = rows[i*2+2]
          h_county[:positive] = string_to_i(rows[i*2+3])
          county_pos += h_county[:positive]
          h[:counties] << h_county
        end
      else
        @errors << 'incorrect table'
      end
    else
      @errors << "missing positive"
    end
    # TOOD death data
    unless @auto_flag
      url = 'https://www1.nyc.gov/assets/doh/downloads/pdf/imm/covid-19-daily-data-summary.pdf'
      `curl #{url} -o #{@path}#{@st}/#{@filetime}_1.pdf`
      `open #{@path}#{@st}/#{@filetime}_1.pdf`
      puts "enter nyc deaths manually"
      byebug
    end
    if h[:positive] != county_pos
      @errors << "county pos do not add up: #{h[:positive]} vs #{county_pos}"
    end
    h
  end

  def parse_oh(h)
    crawl_page
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
    # TODO tests no avaialbe
    h
  end

  def parse_ok(h)
    crawl_page
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
    crawl_page
    sec = SEC/3
    cols = []
    loop do
      begin
        cols = @driver.find_elements(class: 'card-body').map {|i| i.text.gsub(',','')}.select {|i| i=~/Total Completed Tests/}.first.split("\n")

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
      @warnings << 'missing pending'
    end
    if (x = cols.select {|v,i| v=~/^Total Com/}.first) 
      h[:tested] = string_to_i(x.split.last)
    else
      @errors << 'missing tested'
    end
    if (x = cols.select {|v,i| v=~/^Total Deaths/}.first)
      h[:deaths] = string_to_i(x.split.last)
    else
      @errors << 'missing deaths'
    end
    # counties
    # hospitalized
    h
  end  

  def parse_pa(h)
    crawl_page
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
    cols = @driver.find_elements(class: 'ms-rteTable-default').map {|i| i.text.gsub(',','').gsub(/\s+/,' ')}.select {|i| i=~/County/}[0].split
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
    crawl_page
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
    # TODO no death data
    h
  end

  def parse_sc(h)
    crawl_page
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
    if (x=rows.select {|i| i=~/Negative tests /}[0]) && x.gsub(',','') =~ /Negative tests \(Public Health Laboratory only\) ([0-9]+)/
      h[:negative] = string_to_i($1)
    else
      @errors << "missing negative"
    end
=begin
    if (x=rows.select {|i| i=~/Positive tests/}[0]) && x.gsub(',','') =~ /Positive tests ([0-9]+)/
      h[:positive] = string_to_i($1)
    else
      @errors << "missing positive"
    end
=end
    if @driver.page_source =~ /"([^"]+)arcgis\.com([^"]+)"/
      crawl_page($1 + 'arcgis.com' + $2)
      sec = SEC
      loop do
        if @driver.page_source =~ /src=\"https:\/\/arcg.is([^"]+)/
          crawl_page('https://arcg.is' + $1)
          @s = @driver.find_elements(class: 'dashboard-page').first.text
          if @s =~ /Deaths in Individuals with COVID-19 infection\n([^\n]+)\n/
            h[:deaths] = string_to_i($1)
          else
            @errors << 'missing deaths inner'
          end
          if @s =~ /\nTotal Positive Cases\n([^\n]+)/
            h[:positive] = string_to_i($1)
          else
            @errors << 'missing positive inner'
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
    # TODO tested
    h
  end

  def parse_sd(h)
    crawl_page
    tables = @doc.css('table').map {|i| i.text.gsub(',','').gsub(/\s+/,' ').gsub('*','')}
    if (t = tables.select {|i| i=~/SOUTH DAKOTA CASE COUNTS/}[0]) &&
      t =~ /Positive ([0-9]+) Negative ([0-9]+) Pending ([0-9]+)/
      h[:positive] = string_to_i($1)
      h[:negative] = string_to_i($2)
      h[:pending] = string_to_i($3)
    else
      @errors << "missing pos neg pending"
    end
    if (t = tables.select {|i| i=~/COVID-19 IN SOUTH DAKOTA/}[0]) &&
      t =~ /Cases ([0-9]+) Deaths ([0-9]+) Recovered ([0-9]+)/
      h[:deaths] = string_to_i($2)
      h[:recovered] = string_to_i($3)
    else
      @errors << "missing deaths"
    end
    h
  end  

  def parse_tn(h)
    crawl_page
    #byebug
    s = @doc.css('table')[0].text.gsub(',','')
    if s =~ /Laboratory Type\n\nPositive Test\n\nNegative Tests\n\nTotal/ &&
      s =~ /\nTotal\n\n([0-9]+)\n\n([0-9]+)\n\n([0-9]+)/
      h[:positive] = string_to_i($1)
      h[:negative] = string_to_i($2)
      h[:tested] = string_to_i($3)
    else     
      @errors << 'parse failed' 
    end
    s = @doc.css('table').map {|i| i.text.gsub(',','')}.select {|i| i=~/Fatalities/}.first
    if s =~ /Fatalities\n([0-9]+)/
      h[:deaths] = string_to_i($1)
    else
      @errors << 'missing deaths'
    end
    h
  end

  def parse_tx(h)
=begin
    crawl_page
    if @url = @s.scan(/[^'"]+maps\.arcgis\.com\/apps\/opsdashboard[^'"]+/).first
      crawl_page
    else
      @errors << 'missing url'
      return h
    end
=end
# TODO this might break 
@url = 'https://txdshs.maps.arcgis.com/apps/opsdashboard/index.html#/ed483ecd702b4298ab01e8b9cafc8b83'
crawl_page
    sec = SEC
    loop do
      @s = @driver.find_elements(class: 'dashboard-page')[0].text
      flag = true
      if x = @s.scan(/([^\n]+)\nTotal tests/i).first
        h[:tested] = string_to_i(x[0])
      else
        flag = false
      end
      if x = @s.scan(/\n([^\n]+)\nCases Reported\n([^\n]+)\nDeaths\n/).first
        h[:positive] = string_to_i(x[0])
        h[:deaths] = string_to_i(x[1])
      else
        flag = false
      end 
      sec -= 1
      if flag
        break
      elsif sec == 0
        @errors << 'parse failed'
        break
      end
      puts 'sleeping'
      sleep 1
    end
    h
  end

  def parse_ut(h)
    crawl_page
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
  end

  def parse_va(h)
    crawl_page
    if @auto_flag
      puts "skipping VA"
      h[:skip] = true
      return h
    end
    if @driver.page_source =~ /<iframe src=\"https:\/\/public\.tableau\.com([^"]+)"/
      @url = 'https://public.tableau.com' + $1
    else
      @errors << 'missing tableau url'
      return h
    end 
    crawl_page
    @driver.find_element(:xpath, '//*[@id="download-ToolbarButton"]').click
    @driver.find_element(:xpath, '//*[@id="DownloadDialog-Dialog-Body-Id"]/div/button[4]').click
    sleep 3
    @driver.find_element(:xpath, '//*[@id="PdfDialog-Dialog-Body-Id"]/div/div[2]/div[4]/button').click
    sleep 5
    reader = PDF::Reader.new(File.join(ENV['userprofile'], "Downloads", "Virginia COVID-19 Dashboard.pdf"))
    result = reader.page(1).text
    # TODO save this pdf in /data/va dir
    # might want to reference other text to make sure it hasn't changed
    # page.text.gsub(/\s+/, ' ').gsub(',','') =~ /Number of People Tested\^ Cases\*? Hospitalizations Deaths ([0-9]+) ([0-9]+) ([0-9]+) ([0-9]+)/
    resultArray = result.gsub(/\s+/, ' ').gsub(',','').scan(/\d+/).map(&:to_i)
    h[:tested] = resultArray[1]
    h[:positive] = resultArray[2]
    h[:hospitalized] = resultArray[3]
    h[:negative]
    h[:pending]
    h[:deaths] = resultArray[4]
    h
  end
  
  def parse_vt(h)
    crawl_page
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
    crawl_page
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
    if (i=cols.find_index("County Positive/Confirmed Cases Deaths")) && (cols[i+33] =~ /^Yakima/)
      h[:counties] = []
      (i+1..(i+33)).to_a.each do |j|
        if cols[j].gsub(',','') =~ /(.*)\s([\d]+)\s([\d]+)/
          h_county = {}
          h_county[:name] = $1
          h_county[:positive] = string_to_i($2)
          h_county[:death] = string_to_i($3)
          h[:counties] << h_county
        else
          @errors << 'county parse error'
        end
      end
    else
      @errors << 'counties failed'
    end 
    h
  end

  def parse_wi(h)
    crawl_page
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
  end

  def parse_wv(h)
    crawl_page
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
    crawl_page
    s = @driver.find_element(class: 'page').text
    #byebug
    if s =~ /At this time there are ([^\s]+) reported cases/
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
    # TODO no death data
    h
  end

  ######################################

  # look for a word on the webpage
  # deprecated, not used
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
    if !s
      byebug unless @auto_flag
      nil
    end
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

profile = Selenium::WebDriver::Firefox::Profile.new
#profile.add_extension("/path/to/extension.xpi")
profile['browser.download.dir'] = '/Users/danny/Downloads'
#profile['browser.download.folderList'] = 2
profile['browser.helperApps.neverAsk.saveToDisk'] = "application/pdf, application/csv"
profile['pdfjs.disabled'] = true
options = Selenium::WebDriver::Firefox::Options.new(profile: profile)

    @driver = Selenium::WebDriver.for :firefox, options: options
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

  def crawl_page(url = @url)
    begin
      @driver.navigate.to(url)
      open("#{@path}#{@st}/#{@filetime}_#{@page_count+=1}", 'w') do |f| 
        f.puts url
        f.puts @driver.page_source
      end
    rescue => e
      @errors << "crawl_page failed: #{e.inspect}"
    end
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
    skip_flag = OFFSET
    @filetime = Time.now.to_s[0..18].gsub(' ', '-').gsub(':', '.')

    for @st, @url in (open('states.csv').readlines.map {|i| i.strip.split("\t")}.map {|st, url| [st.downcase, url]})
      @page_count = 0 # used for naming saved page
      next if crawl_list.size > 0 && !(crawl_list.include?(@st))
      puts "CRAWLING: #{@st}"
      skip_flag = false if @st == OFFSET
      next if skip_flag
      next if SKIP_LIST.include?(@st)
      unless Dir.exist?("#{@path}#{@st}")
        Dir.mkdir("#{@path}") unless Dir.exist?("#{@path}")
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
        open("#{@path}#{@st}/#{@filetime}", 'w') {|f| f.puts @s} # @s might be modified in parse
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
