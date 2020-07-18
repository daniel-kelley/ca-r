#
#  rframe.rb
#
#  Copyright (c) 2020 by Daniel Kelley
#
# Keep data in a form issuable as an R data frame.
#

class RFrame

  attr_reader :data
  attr_reader :frame_format

  # desc is an array of key value pairs of data name and data type
  # R frame index is handled separately and assumed to be an index.
  # The first item in the frame header is assumed to be the index.
  def initialize(*desc)
    @data = {} # key if header[0].key
    @desc = desc
    @nidx = {}
    @header = {}
    ffa = ['"integer"'] # frame index
    @desc.each_with_index do |col_desc, kvi|
      col_desc_keys = col_desc.keys
      raise "oops #{col_desc_keys.inspect}" if col_desc_keys.length != 1
      k = col_desc_keys[0]
      raise "dup key #{k}" if !@header[k].nil?
      @header[k] = kvi+1 # 0 is frame index
      ffa << "'"+col_desc[k]+"'"
    end
    @frame_format = ffa.join(',')
  end

  # Set data item 'name' (from desc) to 'value' at 'key'
  def set_value(key, name, value)
    raise "#{key} #{name}" if value.nil?
    if @data[key].nil?
        @data[key] = {}
    end
    raise "dup value" if !@data[key][name].nil?
    @data[key][name] = value
  end

  # Increment data item 'name' (from desc) to 'value' at 'key'
  # key and name must already exist
  def incr_value(key, name, value)
    if @data[key].nil?
        @data[key] = {}
    end
    if @data[key][name].nil?
        @data[key][name] = 0
    end
    @data[key][name] = @data[key][name] + value
  end

  # Set data item 'name' to value if it doesn't exist
  def default_value(key, name, value)
    raise 'oops' if @data[key].nil?
    if @data[key][name].nil?
      @data[key][name] = value
    end
  end

  # Return the data frame descriptor string
  def desc_str
    a = []
    @desc.each { |d| a << d.keys[0] }
    a.join(' ')
  end

  # Return an R data frame as an array of lines first element of the
  # array is the column names and each subsequent element of the array
  # is a row that starts with an index number followed by each column
  # in descriptor order
  def get_a
    a = []
    a << desc_str
    idx = 1
    @data.sort.each do |k,row_data|
      row = [idx, k] # first two elements are index and key
      row_data.each do |column_name,value|
        col_idx = @header[column_name]
        raise "oops #{column_name} #{@header.inspect}" if col_idx.nil?
        raise "oops" if !row[col_idx].nil?
        row[col_idx] = value
      end
      # sanity check - all columns should be non-nil
      row.each { |e| raise "oops #{row.inspect}" if e.nil? }
      a << row.join(' ')
      idx += 1
    end
    a
  end

end
