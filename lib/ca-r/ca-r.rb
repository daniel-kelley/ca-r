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
require_relative 'rframe'

class CA_R

  LIBDIR = File::dirname __FILE__
  DATA = "#{LIBDIR}/../../data/"
  REGION_TO_COUNTY = YAML::load(File.open("#{DATA}/ca-region.yml"))

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

  # Return a date string as a canonical R format date string key
  def date_key(date_str)
    y,m,d = date_str.split('-')
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
    return true if !only.nil? && county != only
    return false
  end

  # Convert case data
  def convert_case(data, case_csv, frame_format, only)
    CSV.foreach(case_csv) do |row|
      error = 0
      county = row[0]
      # r row CSV                      data
      # - 0   county,                  <data key>
      # 0 1   totalcountconfirmed,     C
      # 1 2   totalcountdeaths,        D
      # 2 3   newcountconfirmed,       I
      # 3 4   newcountdeaths,          F
      # - 5   date                     dates

      next if skip_row(county,only)

      raise "oops #{county}" if @region[county].nil?

      if data[county].nil?
        # Note: column names 'dates' and 'I' are dictated by estimate_R
        # E tracks conversion errors
        data[county] = RFrame.new(*frame_format)
      end
      # date handling
      dstr = date_key(row[5])

      @as_of_date = [dstr,@as_of_date].max

      # CSV data conversion
      r = row[1..4].map do |e|
        if e.nil?
          error += 1
          0
        else
          v = e.to_i
          if v < 0
            error += 1
            v = 0
          end
          v
        end
      end

      data[county].set_value(dstr, "I", r[2])
      data[county].set_value(dstr, "C", r[0])
      data[county].set_value(dstr, "D", r[1])
      data[county].set_value(dstr, "F", r[3])
      data[county].set_value(dstr, "E", error)
    end
  end

  # Convert hospital data
  def convert_hosp(data, hosp_csv, only)
    CSV.foreach(hosp_csv) do |row|
      error = 0
      county = row[0]

      # r row CSV                                         data
      # - 0   county,                                     <data key>
      # - 1   todays_date,                                dates
      # 0 2   hospitalized_covid_confirmed_patients,      HC
      # 1 3   hospitalized_suspected_covid_patients,      HS
      # 2 4   hospitalized_covid_patients,                HP
      # 3 5   all_hospital_beds,                          HB
      # 4 6   icu_covid_confirmed_patients,               IC
      # 5 7   icu_suspected_covid_patients,               IS
      # 6 8   icu_available_beds                          IB

      next if skip_row(county,only)

      raise "oops #{county}" if data[county].nil?

      # date handling
      dstr = date_key(row[1])

      # CSV data conversion
      r = row[2..8].map do |e|
        if e.nil?
          # A lot of empty data so don't treat as an error
          0
        else
          v = e.to_i
          if v < 0
            # Not expecting negative
            error += 1
            v = 0
          end
          # CSV format is floating point but these are expected to be counts
          #
          vf = e.to_f
          vi = vf.to_i
          if (vf - vi > 0.0001)
            raise "unexpected #{e}"
          end
          v
        end
      end

      data[county].set_value(dstr, "HC", r[0])
      data[county].set_value(dstr, "HS", r[1])
      data[county].set_value(dstr, "HP", r[2])
      data[county].set_value(dstr, "HB", r[3])
      data[county].set_value(dstr, "IC", r[4])
      data[county].set_value(dstr, "IS", r[5])
      data[county].set_value(dstr, "IB", r[6])

      if error != 0
        data[county].incr_value(dstr, "E", error)
      end

    end
  end

  # Groom hospital data
  #   Not every incidence date has corresponding hospital data
  #   Set any missing hospital data to zero
  def groom_hosp(data, only)
    data.each do |county, frame|
      next if !only.nil? && county != only
      frame.data.each_key do |dstr|
        frame.default_value(dstr, "HC", 0)
        frame.default_value(dstr, "HS", 0)
        frame.default_value(dstr, "HP", 0)
        frame.default_value(dstr, "HB", 0)
        frame.default_value(dstr, "IC", 0)
        frame.default_value(dstr, "IS", 0)
        frame.default_value(dstr, "IB", 0)
      end
    end
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
  def convert(case_csv, hosp_csv, only=nil)
    data = {}
    frame_format = [
      {"dates"=>"Date"},
      {"I"=>"integer"},
      {"C"=>"integer"},
      {"D"=>"integer"},
      {"F"=>"integer"},
      {"E"=>"integer"},
      {"HC"=>"integer"},
      {"HS"=>"integer"},
      {"HP"=>"integer"},
      {"HB"=>"integer"},
      {"IC"=>"integer"},
      {"IS"=>"integer"},
      {"IB"=>"integer"},
    ]

    convert_case(data, case_csv, frame_format, only)
    convert_hosp(data, hosp_csv, only)
    groom_hosp(data, only)
    groom_case(data, only)

    # append region data
    # append state data
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

  # Generate R commands and data for all geographic entities
  def gen_all(case_csv:, hosp_csv:, dir:)
    pn = Pathname.new(dir)
    out_dir = pn.cleanpath
    FileUtils.mkdir_p(out_dir)
    data = convert(case_csv, hosp_csv)
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
  def gen_only(case_csv:, hosp_csv:, county:)
    data = convert(case_csv, hosp_csv, county)
    waf("/proc/self/fd/1", data[county].get_a)
  end

end
