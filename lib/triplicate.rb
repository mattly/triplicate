require 'time'
module Triplicate
  
  def self.included(base)
    base.extend ClassMethods
  end
  
  attr_reader :document
  
  def initialize(doc={})
    @document = doc
  end
  
  def [](key)
    if readable?(key)
      key = key.to_s
      @document[key] = Triplicate.coerce(@document[key], coercion(key))
      @document[key] || default(key)
    end
  end
  
  def []=(key, value)
    if writeable?(key)
      @document[key.to_s] = Triplicate.coerce(value, coercion(key))
    end
  end
  
  def field(key)
    self.class.fields[key.to_s]
  end
  
  def readable?(key)
    field(key)[:read]
  end
  
  def writeable?(key)
    field(key)[:write]
  end
  
  def default(key)
    field(key)[:default]
  end
  
  def coercion(key)
    field(key)[:coerce]
  end
  
  module ClassMethods
    
    def field(*keys)
      opts = keys.last.respond_to?(:has_key?) ? keys.pop : {}
      [keys].flatten.each do |key|
        fields[key.to_s] = {
          :read => true,
          :write => true,
          :default => opts[:default],
          :coerce => opts[:coerce]
        }
      end
    end
    
    def fields
      @fields ||= Hash.new{|hash, key| hash[key] = {} }
    end
    
  end
    
  COERCIONS = {}
  COERCIONS[String]         = lambda{|v| v.to_s }
  COERCIONS[Fixnum]         = lambda{|v| v.to_i }
  COERCIONS[Integer]        = lambda{|v| v.to_i }
  COERCIONS[Float]          = lambda{|v| v.to_f }
  COERCIONS[TrueClass]      = lambda{|v| Triplicate.truthy?(v) }
  COERCIONS[FalseClass]     = lambda{|v| Triplicate.truthy?(v) }
  COERCIONS[Time]           = lambda{|v| Time.parse(v) }
  COERCIONS[Range]          = lambda do |v|
    raise unless v =~ /^(\d+|\d+\.\d+)(\.{2,3})(\d+|\d+\.\d+)$/
    start, middle, tail = $1, $2, $3
    start = start =~ /\./ ? start.to_f : start.to_i
    tail  = tail  =~ /\./ ? tail.to_f  : tail.to_i
    Range.new(start, tail, middle == "...")
  end
  
  def self.coerce(value, coercion)
    if coercion.nil?
      value
    elsif value.kind_of?(coercion)
      value
    elsif value.is_a?(Hash) && value.has_key?('json_class') && coercion.responds_to?(:json_create)
      coercion.json_create(value)
    elsif conversion = COERCIONS[coercion]
      conversion.call(value)
    else
      coercion.new(value)
    end
  end
  
  def self.truthy?(value)
    case value
    when Array
      arr = value.flatten.compact
      if arr.size == 1
        truthy?(arr.first)
      else
        !arr.empty?
      end
    when String
      value.strip.gsub(/0+\.?\0*/,'').size > 0
    when Numeric
      value != 0
    else
      !!value
    end
  end
  
end