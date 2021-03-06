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
  # Groom the header so CSV can parse it.
  #
  def groom_header(hdr)
    @hdr_str = hdr.join(' ').chomp
    @hdr_str.gsub!("\n",'')
    r = []
    CSV.new(@hdr_str).each do |row|
      r << row
    end
    raise 'oops' if r.length != 1
    @hdr=r[0]
  end

  def lookup(key, row)
    @hdr.each_with_index do |h,i|
      if h =~ key
        return row[i]
      end
    end
    raise "Cannot find header key #{s}"
  end

  #
  # Add the CSV row to @data
  #
  # Only add data needed for app_data to improve robustness over header
  # changes.
  #
  def add_row(row)
    #pp row
    @data[lookup(/County/,row)] = {
      # 'ROW' => row,
      # 'assessment_date' => lookup(/Date of Tier Assessment/,row),
      # 'ending_date' => lookup(/Ending Date/,row),
      'final_tier' => groom_integer(lookup(/Final Tier/,row)),
      'previous_tier' => groom_integer(lookup(/Previous Tier/,row)),
      #'starting_date' => lookup(//,row),
      'current_tier' => groom_integer(lookup(/Tier for Week/,row)),
      'test_positivity' => groom_float(lookup(/Test Positivity/,row)),
      #'adjusted_case_rate' => groom_float(lookup(//,row)),
      #'unadjusted_case_rate' => groom_float(lookup(//,row)),
      #'adjustment_factor' => groom_float(lookup(//,row)),
      'tests_per_100k' => groom_float(lookup(/Tests per 100,000/,row)),
      'population' => groom_integer(lookup(/Population/,row)),
      #'HEQ_positivity' => groom_float(lookup(//,row)),
    }
  end

  # WAR for malformed CSV header: just skip header until the first county
  def groom(csv)
    h = []
    a = []
    skip = true
    csv.each_line do |line|
      if line =~ /Alameda/
        skip = false
      end
      if skip
        h << line
      else
        a << line
      end
    end
    groom_header(h)
    body = a.join("\r\n")
    body
  end

  # Scan chart data and convert to internal format
  #

  # CSV Header is a moving target. Just like CA Covid-19 eligibility
  # requirements. This might explain things.
  def scan_chart(csv)
    body = groom(csv)
    CSV.new(body).each do |row|
      error = 0
      county = lookup(/County/, row)
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

  # Save header info for debugging
  def debug_hdr(dir)
    d = [@hdr.length,@hdr, @hdr_str]
    File.open("#{dir}/ca-tier-hdr.yml", "w") do |f|
      f.puts(d.to_yaml)
    end
  end


  # Generate YAML and header debug data
  def generate(out)
    dir = File.dirname(out)
    File.open(out, "w") { |f| f.puts(@data.to_yaml) }
    debug_hdr(dir)
  end

end
