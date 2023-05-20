#
#  ca-r.rb
#
#  Copyright (c) 2020 by Daniel Kelley
#

require 'pp'
require 'csv'
require 'yaml'
require 'pathname'
require 'fileutils'
require 'date'
require_relative 'rframe'

class CA_R

  LIBDIR = File::dirname __FILE__
  DATA = "#{LIBDIR}/../../data/"
  REGION_TO_COUNTY = YAML::load(File.open("#{DATA}/ca-region.yml"))
  # Match start date to previous statewide_cases data file. Backfilled
  # case data in covid19cases_test causes crazy R0 values and throws
  # off the verical scale, making comparisons of the old and new data
  # sets difficult. Making the start dates match gets rid of most of
  # the crazyness.
  START_DATE = Date.parse("2020/03/18")

  # Initialize this instance
  def initialize
    load_region_data
    @as_of_date = ""
  end

  # load region data and invert
  def load_region_data
    @region = {}
    REGION_TO_COUNTY.each do |region,county_list|
      county_list.each { |county| @region[county]=region }
    end
  end

  # write array to file
  def waf(file, ary)
    File.open(file,"w") do |f|
      ary.each { |line| f.puts line }
    end
  end

  # Parse date with "American" mon/day/year format
  def parse_date(datestr)
    if datestr =~ %r{(\d\d)/(\d\d)/(\d\d\d\d)}
      # mon/day/year
      datestr = "#{$3}-#{$1}-#{$2}"
    end
    begin
      return Date.parse(datestr)
    rescue
      return START_DATE - 1
    end
  end

  # Return a date string as a canonical R format date string key
  def date_key(datestr)
    date = parse_date(datestr)
    y = date.year
    m = date.mon
    d = date.day
    mstr = "%02d"%m.to_i
    dstr = "%02d"%d.to_i
    ystr = y.to_i
    "#{ystr}/#{mstr}/#{dstr}"
  end

  def skip_row(county, only)
    return true if county =~ /^county/
    # may eventually keep unassigned for statewide calculations
    return true if county =~ /^Unassigned/
    return true if county =~ /^Out Of Country/
    return true if county =~ /^Out of state/
    return true if county =~ /^Unknown/
    return true if !only.nil? && county != only
    return false
  end

  def skip_date(datestr)
    date = parse_date(datestr)
    date < START_DATE
  end

  # Convert case data (new covid19cases_test.csv)
  def convert_covid19cases_test(data, case_csv, frame_format, only)
    idx = 0
    CSV.foreach(case_csv) do |row|
      #  r row CSV                          data
      #  - 0   date
      #  - 1   area                         <data key> if area_type == County
      #  - 2   area_type
      #  0 3   population
      #  1 4   deaths                       F
      #  2 5   cumulative_deaths            D
      #  3 6   total_tests
      #  4 7   cumulative_total_tests
      #  5 8   positive_tests               I
      #  6 9   cumulative_positive_tests    C

      error = 0
      county = row[1]

      idx += 1

      if idx == 1
        # Double check header
        raise 'oops' if row[0] != 'date'
        raise 'oops' if row[1] != 'area'
        raise 'oops' if row[2] != 'area_type'
        raise 'oops' if row[3] != 'population'
        raise 'oops' if row[4] != 'deaths'
        raise 'oops' if row[5] != 'cumulative_deaths'
        raise 'oops' if row[6] != 'total_tests'
        raise 'oops' if row[7] != 'cumulative_total_tests'
        raise 'oops' if row[8] != 'positive_tests'
        raise 'oops' if row[9] != 'cumulative_positive_tests'
      end

      next if row[0].nil? # skip empty dates
      next if row[2] != "County" # only look at area type County
      next if skip_row(county,only)

      raise "oops #{county}" if @region[county].nil?

      if data[county].nil?
        # Note: column names 'dates' and 'I' are dictated by estimate_R
        # E tracks conversion errors
        data[county] = RFrame.new(*frame_format)
      end
      # date handling
      dstr = date_key(row[0])
      next if dstr =~ /^$/
      next if skip_date(dstr)

      @as_of_date = [dstr,@as_of_date].max

      # CSV data conversion
      r = row[3..-1].map do |e|
        if e.nil?
          error += 1
          0
        else
          begin
            v = Float(e)
          rescue
            v = 0.0
            error += 1
          end
          if v < 0.0
            error += 1
            v = 0
          end
          v
        end
      end

      data[county].set_value(dstr, "I", r[5].to_i)
      data[county].set_value(dstr, "C", r[6].to_i)
      data[county].set_value(dstr, "F", r[1].to_i)
      data[county].set_value(dstr, "D", r[2].to_i)
      data[county].set_value(dstr, "E", error)

    end
  end

  def convert_case(data, case_csv, frame_format, only)
    convert_covid19cases_test(data, case_csv, frame_format, only)
  end

  # Groom case data
  #   Not every hospital date has corresponding incidence data
  #   Set any missing incidence data to zero
  def groom_case(data, only)
    data.each do |county, frame|
      next if !only.nil? && county != only
      frame.data.each_key do |dstr|
        frame.default_value(dstr, "I", 0)
        frame.default_value(dstr, "C", 0)
        frame.default_value(dstr, "D", 0)
        frame.default_value(dstr, "F", 0)
        frame.default_value(dstr, "E", 1)
      end
    end
  end

  # Convert csv file to hash of R Frames indexed by geographic
  # entity. If 'only' is not nil, only do conversion for given entity.
  def convert(case_csv, only=nil)
    data = {}
    frame_format = [
      {"dates"=>"Date"},
      {"I"=>"integer"},
      {"C"=>"integer"},
      {"D"=>"integer"},
      {"F"=>"integer"},
      {"E"=>"integer"},
    ]

    convert_case(data, case_csv, frame_format, only)
    groom_case(data, only)
    data
  end

  # Construct R commands to ggplot the given data
  def ggplot(cvar, col_name, geom='line', mean_col_name=nil)
    s = "#{cvar}_g_#{col_name} <- ggplot(data=#{cvar}, aes(dates, #{col_name}))+geom_#{geom}()+"
    if !mean_col_name.nil?
      s << "geom_line(aes(dates,#{mean_col_name}),color=\"red\")+"
    end
    s << "scale_x_date(date_minor_breaks = \"1 week\")"
  end

  # Construct R commands to process geographic entity data (with hosp)
  def cprocess_old(dir, cvar, cfile, rscript)
    rscript << "print(\"#{cvar}\")"
    rscript << "#{cvar} <- read.table(\"#{cfile}\",colClasses = c_col)"

    rscript << "#{cvar}_uncertain_si <- estimate_R(#{cvar},method = \"uncertain_si\",config = si_config)"

    rscript << "write_yaml(#{cvar}_uncertain_si, \"#{dir}/#{cvar}_R.yml\")"
    rscript << "svg('#{dir}/#{cvar}_uncertain_si.svg')"
    rscript << "plot(#{cvar}_uncertain_si)"
    rscript << "dev.off()"

    # I
    rscript << "#{cvar}_I_Z <- zoo(#{cvar}$I, #{cvar}$dates)"
    rscript << "#{cvar}_I_m <- rollmean(#{cvar}_I_Z, 7,fill = list(NA, NA, NA, NULL, NA ,NA, NA))"
    rscript << "#{cvar}$I_m = coredata(#{cvar}_I_m)"
    rscript << ggplot(cvar, 'I','col','I_m')
    rscript << "ggsave('#{dir}/#{cvar}_I.svg', #{cvar}_g_I)"

    # C
    rscript << ggplot(cvar, 'C')
    rscript << "ggsave('#{dir}/#{cvar}_C.svg', #{cvar}_g_C)"

    # D
    rscript << ggplot(cvar, 'D')
    rscript << "ggsave('#{dir}/#{cvar}_D.svg', #{cvar}_g_D)"

    # E
    rscript << ggplot(cvar, 'E', 'col')
    rscript << "ggsave('#{dir}/#{cvar}_E.svg', #{cvar}_g_E)"

    # HC
    rscript << ggplot(cvar, 'HC', 'col')
    rscript << "ggsave('#{dir}/#{cvar}_HC.svg', #{cvar}_g_HC)"

    # HS
    rscript << ggplot(cvar, 'HS', 'col')
    rscript << "ggsave('#{dir}/#{cvar}_HS.svg', #{cvar}_g_HS)"

    # HP
    rscript << ggplot(cvar, 'HP', 'col')
    rscript << "ggsave('#{dir}/#{cvar}_HP.svg', #{cvar}_g_HP)"

    # HB
    rscript << ggplot(cvar, 'HB', 'col')
    rscript << "ggsave('#{dir}/#{cvar}_HB.svg', #{cvar}_g_HB)"

    # IC
    rscript << ggplot(cvar, 'IC', 'col')
    rscript << "ggsave('#{dir}/#{cvar}_IC.svg', #{cvar}_g_IC)"

    # IS
    rscript << ggplot(cvar, 'IS', 'col')
    rscript << "ggsave('#{dir}/#{cvar}_IS.svg', #{cvar}_g_IS)"

    # IB
    rscript << ggplot(cvar, 'IB', 'col')
    rscript << "ggsave('#{dir}/#{cvar}_IB.svg', #{cvar}_g_IB)"

    # Save updated data frame as YAML
    rscript << "write_yaml(#{cvar}, \"#{dir}/#{cvar}_Data.yml\")"

  end

  # Construct R commands to process geographic entity data
  def cprocess(dir, cvar, cfile, rscript)
    rscript << "print(\"#{cvar}\")"
    rscript << "#{cvar} <- read.table(\"#{cfile}\",colClasses = c_col)"

    rscript << "#{cvar}_uncertain_si <- estimate_R(#{cvar},method = \"uncertain_si\",config = si_config)"

    rscript << "write_yaml(#{cvar}_uncertain_si, \"#{dir}/#{cvar}_R.yml\")"
    rscript << "svg('#{dir}/#{cvar}_uncertain_si.svg')"
    rscript << "plot(#{cvar}_uncertain_si)"
    rscript << "dev.off()"

    # I
    rscript << "#{cvar}_I_Z <- zoo(#{cvar}$I, #{cvar}$dates)"
    rscript << "#{cvar}_I_m <- rollmean(#{cvar}_I_Z, 7,fill = list(NA, NA, NA, NULL, NA ,NA, NA))"
    rscript << "#{cvar}$I_m = coredata(#{cvar}_I_m)"
    rscript << ggplot(cvar, 'I','col','I_m')
    rscript << "ggsave('#{dir}/#{cvar}_I.svg', #{cvar}_g_I)"

    # C
    rscript << ggplot(cvar, 'C')
    rscript << "ggsave('#{dir}/#{cvar}_C.svg', #{cvar}_g_C)"

    # D
    rscript << ggplot(cvar, 'D')
    rscript << "ggsave('#{dir}/#{cvar}_D.svg', #{cvar}_g_D)"

    # E
    rscript << ggplot(cvar, 'E', 'col')
    rscript << "ggsave('#{dir}/#{cvar}_E.svg', #{cvar}_g_E)"

    # Save updated data frame as YAML
    rscript << "write_yaml(#{cvar}, \"#{dir}/#{cvar}_Data.yml\")"

  end

  # Generate R commands and data for all geographic entities
  def gen_all(case_csv:, dir:)
    pn = Pathname.new(dir)
    out_dir = pn.cleanpath
    FileUtils.mkdir_p(out_dir)
    data = convert(case_csv)
    rscript = []
    data.each do |county, cdata|
      if rscript.length == 0
        rscript << "c_col <- c("+cdata.frame_format+")"
      end
      cvar=county.gsub(' ','_').downcase
      cfile = "#{out_dir}/#{cvar}.data"
      waf(cfile, cdata.get_a)
      cprocess(out_dir, cvar,cfile,rscript)
    end
    waf("#{out_dir}/process.R", rscript)
    waf("#{out_dir}/DATE.txt", [@as_of_date])
  end

  # Print R frame data for given geographic entity
  def gen_only(case_csv:, county:)
    data = convert(case_csv, county)
    waf("/proc/self/fd/1", data[county].get_a)
  end

end
