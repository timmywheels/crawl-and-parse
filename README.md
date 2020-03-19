# covid-19-crawler

The main script, crawler.rb, crawls the webpages for each of the 50 states
and DC for their published COVID-19 statistics.

This was a weekend hack, so pardon the messy code. The object was to get
something working and pulling data from the state websites as soon as possible.

Help to improve the crawlers would be much appreciated. A few sites have images
that require manual review, and a few js page crawls are unfinished.

The crawled data is being hosted on http://coronavirusapi.com/
That project could also use help!

Thanks, and stay safe!

## Setting up this repo

- Install [bundle](https://bundler.io/). Bundler provides a consistent environment for Ruby projects by tracking and installing the exact gems and versions that are needed.
- If bundle is installed, run `bundle install` to install dependencies
- Run `ruby crawler.rb`. This script reads `states.csv` which contains a URL to a coronavirus webpage for each state in the USA, including DC. It crawls these webpages and collects the data for each state. It compares the previously scraped data with the current scraped data and saves all the data into `all.csv`.
