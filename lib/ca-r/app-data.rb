#
#  app-data.rb
#
#  Copyright (c) 2020 by Daniel Kelley
#

require 'yaml'
require 'json'
require 'fileutils'

class APP_DATA

  # Description/color from
  #   https://covid19.ca.gov/safer-economy/#county-status
  TIER_DESC = {
    1 => 'Widespread',
    2 => 'Substantial',
    3 => 'Moderate',
    4 => 'Minimal'
  }

  TIER_COLOR = {
    1 => 'purple',
    2 => 'red',
    3 => 'orange',
    4 => 'yellow'
  }

  def initialize(tier_data)
    @tier_data = yaml_load(tier_data)
  end

  def yaml_load(file)
    File.open(file) { |yf| YAML::load(yf) }
  end

  def get_tier(county)
    data = @tier_data[county]
    raise "oops: missing tier data for #{county}" if data.nil?
    data
  end

  def get_tier_value(tier, key)
    value = tier[key]
    raise "missing #{key}" if value.nil?
    value
  end

  def get_tier_quick(county)
    tier = get_tier(county)
    final = TIER_DESC[get_tier_value(tier, 'final_tier')]
    prev = TIER_DESC[get_tier_value(tier, 'previous_tier')]
    return (final == prev) ? "#{final}" : "#{prev}->#{final}"
  end

  def detail(cvar, name, ad)
    tier = get_tier(name)
    final_tier = TIER_DESC[get_tier_value(tier, 'final_tier')]
    previous_tier = TIER_DESC[get_tier_value(tier, 'previous_tier')]
    current_tier = TIER_DESC[get_tier_value(tier, 'current_tier')]
    final_color = TIER_COLOR[get_tier_value(tier, 'final_tier')]
    previous_color = TIER_COLOR[get_tier_value(tier, 'previous_tier')]
    current_color = TIER_COLOR[get_tier_value(tier, 'current_tier')]
    final_style = "background-color: #{final_color}"
    previous_style = "background-color: #{previous_color}"
    current_style = "background-color: #{current_color}"
    test_positivity = get_tier_value(tier, 'test_positivity')
    tests_per_100k = get_tier_value(tier, 'tests_per_100k')
    population = get_tier_value(tier, 'population')

    em = ad['estimate_R_mean']
    es = ad['estimate_R_std']
    aI = ad['I']
    aC = ad['C']
    aD = ad['D']
    aE = ad['E']
    s = <<-"EOF"
    <html>
      <body>
      <table>
      <tr><td>County</td><td>#{name}</td></tr>
      <tr><td>Estimated R</td><td>#{em}(#{es})</td></tr>
      <tr><td>Daily Incidence</td><td>#{aI}</td></tr>
      <tr><td>Cumulative Incidence</td><td>#{aC}</td></tr>
      <tr><td>Cumulative Deaths</td><td>#{aD}</td></tr>
      <tr><td>Conversion Errors</td><td>#{aE}</td></tr>
      <tr><td>Final Tier</td><td style='#{final_style}'>#{final_tier}</td></tr>
      <tr><td>Previous Tier</td><td style='#{previous_style}'>#{previous_tier}</td></tr>
      <tr><td>Current Tier</td><td style='#{current_style}'>#{current_tier}</td></tr>
      <tr><td>Test Positivity</td><td>#{test_positivity}</td></tr>
      <tr><td>Tests/100k</td><td>#{tests_per_100k}</td></tr>
      <tr><td>Population</td><td>#{population}</td></tr>
      </table>
    <h3>Daily Incidence</h3>
      <br><img src='#{cvar}_I.svg' width='50%' height='50%'/></br>
    <h3>Cumulative Incidence</h3>
      <br><img src='#{cvar}_C.svg' width='50%' height='50%'/></br>
    <h3>Cumulative Deaths</h3>
      <br><img src='#{cvar}_D.svg' width='50%' height='50%'/></br>
    <h3>Conversion Errors</h3>
      <br><img src='#{cvar}_E.svg' width='50%' height='50%'/></br>
    <h3>Estimated R</h3>
      <br><img src='#{cvar}_uncertain_si.svg'/></br>
  </body>
      </html>
EOF

  s

  end

  def gen(dir:)

    app_data = {}
    pn = Pathname.new(dir)
    out_dir = pn.cleanpath
    FileUtils.mkdir_p(out_dir)

    # Start with <county>_R.yml
    Dir.glob("#{out_dir}/*_R.yml").each do |yfile|
      next if yfile =~ /unassigned/
      s = nil
      cvar = nil
      detail_file = nil
      File.open(yfile) do |yf|
        begin
          y = YAML::load(yf)
          base = File::basename(yfile, ".yml")
          cvar = base.sub('_R','')
          a = cvar.split('_')
          s = a.map {|e| e.capitalize }.join(' ')
          if app_data[s].nil?
            app_data[s] = {}
          end
          problem = 0
          if y.is_a? Hash
            estimate_R_mean = y['R']['Mean(R)'][-1]
            estimate_R_std = y['R']['Std(R)'][-1]
          else
            # Modoc County didn't have any reports early on
            estimate_R_mean = 0
            estimate_R_std = 0
            problem = 1
          end
          detail_file = "#{cvar}_detail.html"
          app_data[s]['estimate_R_mean'] = estimate_R_mean
          app_data[s]['estimate_R_std'] = estimate_R_std
          app_data[s]['problem'] = problem
          app_data[s]['tier'] = get_tier_quick(s)
          app_data[s]['detail'] = detail_file
        rescue
          raise "#{yfile} #{$!}"
        end
      end
      ydata = yfile.sub('_R','_Data')
      File.open(ydata) do |yf|
        begin
          YAML::load(yf).each { |key,ary| app_data[s][key] = ary[-1] }
        rescue
          raise "#{ydata} #{$!}"
        end
      end
      File.open("#{out_dir}/#{detail_file}","w") do |f|
        f.puts detail(cvar, s, app_data[s])
      end
    end

    File.open("#{out_dir}/app_data.js","w") do |f|
      f.puts 'var app_data = '+app_data.to_json+';'
    end

  end

end
