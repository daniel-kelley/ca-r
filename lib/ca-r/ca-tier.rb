#
#  ca-tier.rb
#
#  Copyright (c) 2021 by Daniel Kelley
#

require 'yaml'
require 'nokogiri'
require 'uri-cache'
require 'open-uri'
require 'csv'
require 'pp'

class CA_Tier

  #
  # Initialize instance data
  #
  def initialize
    @data = {} # by county
    @cache = URICache.new("cache")
  end

  #
  # Skip row if it is some sort of header
  #
  def skip_row(county)
    return true if county =~ /^County/
    return true if county =~ /^State/
    return true if county =~ /^\s*$/
    return false
  end

  #
  # Groom floats, blanks to 0.0
  #
  def groom_float(n)
    n =~ /^\s*$/ ? 0.0 : n.to_f
  end

  #
  # Groom integers, blanks to 0.0
  #
  def groom_integer(n)
    n =~ /^\s*$/ ? 0.0 : n.to_i
  end

  #
  # Add the CSV row to @data
  #
  def add_row(row)
    #pp row
    @data[row[0]] = {
      'assessment_date' => row[1],
      'ending_date' => row[2],
      'final_tier' => groom_integer(row[3]),
      'previous_tier' => groom_integer(row[4]),
      'starting_date' => row[5],
      'current_tier' => groom_integer(row[6]),
      'test_positivity' => groom_float(row[7]),
      'adjusted_case_rate' => groom_float(row[8]),
      'unadjusted_case_rate' => groom_float(row[9]),
      'adjustment_factor' => groom_float(row[10]),
      'tests_per_100k' => groom_float(row[11]),
      'population' => groom_integer(row[12]),
      'HEQ_positivity' => groom_float(row[13]),
    }
  end

  # WAR for malformed CSV header: just skip header until the first county
  def groom(csv)
    a = []
    skip = true
    csv.each_line do |line|
      if line =~ /Alameda/
        skip = false
      end
      a << line if !skip
    end
    a.join("\r\n")
  end

  # Scan chart data and convert to internal format
  def scan_chart(csv)
    CSV.new(groom(csv)).each do |row|
      error = 0
      county = row[0]
      #  0 County
      #  1 Date of Tier Assessment
      #  2 Ending Date of Week of Data
      #  3 Final Tier Assignment
      #  4 Previous Tier Assignment
      #  5 First Date in Current Tier
      #  6 Tier for Week
      #  7 Test Positivity
      #  8 Case Rate Used for Tier Adjusted Using Linear Adjustment
      #  9 Unadjusted Case Rate per 100,000
      # 10 Linear Adjustment Factor Applied to Case Rate
      # 11 Tests per 100,000
      # 12 Population
      # 13 Health Equity Quartile Test Positivity
      next if row.length == 0
      next if skip_row(county)
      raise "oops #{row.inspect}" if county.nil?
      county.gsub!('*','') # like "Alpine*"
      add_row(row)
    end
  end


  # Scan the top HTML page looking for the Blueprint Data Chart
  # They are listed in reverse chronological order so the newest one
  # is first.
  def scan_top(doc)
    doc.traverse do |node|
      if node.name == 'a'
        value = node.attribute('href').value
        if value =~ /blueprint_data_chart\w+\.csv$/
          scan_chart(@cache.get(value))
          return
        end
      end
    end
  end

  # Get the data for the top URL. Cache it if we are in debug mode.
  def get_top(url)
    if ENV['DEBUG'].nil?
      URI.open(url) # production
    else
      @cache.get(url) # debug
    end
  end

  # Read latest data from url
  def scan(url)
    # top page isn't static so do not cache
    doc = Nokogiri::HTML(get_top(url))
    scan_top(doc)
    # for method chaining
    return self
  end

  # Generate YAML data
  def generate(out)
    File.open(out, "w") { |f| f.puts(@data.to_yaml) }
  end

end
