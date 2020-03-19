# covid-19-crawler

The main script, crawler.rb, crawls the webpages for each of the 50 states
and DC for their published COVID-19 statistics. 

This was a weekend hack, so pardon the messy code. The object was to get
something working and pulling data from the state websites as soon as possible.

Help to improve the crawlers would be much appreciated. A few sites have images
that require manual review, and a few js page crawls are unfinished.

The crawled data is being hosted on http://coronavirusapi.com/
That project could also use help!

For Windows users, following is required to get up and running:
Install ruby v2.6.X latest
	For Windows: https://rubyinstaller.org/downloads/
After ruby install, open ruby command line and run for each “gem install <X>” for the gems to install listed below
Gems to install
	Ffi
	Selenium-webdriver
	Nokogiri
	Byebug
Install firefox
Install Visual Studio runtime redist from here:
https://support.microsoft.com/en-us/help/2977003/the-latest-supported-visual-c-downloads
Download geckodriver from here:
https://github.com/mozilla/geckodriver/releases
Copy to a location and add to your PATH



Thanks, and stay safe!
