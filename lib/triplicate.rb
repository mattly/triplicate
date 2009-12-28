require 'time'
module Triplicate
  
  def self.included(base)
    base.extend ClassMethods
  end
  
  attr_reader :document
  
  def initialize(doc={})
    @document = doc
  end
    
  module ClassMethods
    
    def self.extended(base)
    end
    
    def field(key, opts={})
      define_method key do
        val = document[key.to_s]
        if opts[:as]
          val = Triplicate.coerce(val, opts[:as])
        end
        val || opts[:default]
      end
      define_method "#{key}=" do |val|
        if opts[:as]
          val = Triplicate.coerce(val, opts[:as])
        end
        document[key.to_s] = val
      end
    end
    
  end
  
  COERCIONS = {}
  COERCIONS[String]         = lambda{|v| v.to_s }
  COERCIONS[Fixnum]         = lambda{|v| v.to_i }
  COERCIONS[Integer]        = lambda{|v| v.to_i }
  COERCIONS[Float]          = lambda{|v| v.to_f }
  COERCIONS[Time]           = lambda{|v| Time.parse(v) }
  COERCIONS[Range]          = lambda do |v|
    raise unless v =~ /^(\d+|\d+\.\d+)(\.{2,3})(\d+|\d+\.\d+)$/
    start, middle, tail = $1, $2, $3
    start = start =~ /\./ ? start.to_f : start.to_i
    tail  = tail  =~ /\./ ? tail.to_f  : tail.to_i
    Range.new(start, tail, middle == "...")
  end
  
  def self.coerce(value, as)
    as = [as].flatten
    as.each do |coercion|
      case coercion
      when Class
        next if value.is_a?(coercion)
        value = if conversion = COERCIONS[coercion]
          conversion.call(value)
        else
          coercion.new(value)
        end
      end
    end
    value
  end
  
end