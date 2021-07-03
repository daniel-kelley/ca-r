#
#  app-data.rb
#
#  Copyright (c) 2020 by Daniel Kelley
#

require 'yaml'
require 'json'
require 'fileutils'

class APP_DATA

  def initialize
  end

  def yaml_load(file)
    File.open(file) { |yf| YAML::load(yf) }
  end

  def detail(cvar, name, ad)
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
