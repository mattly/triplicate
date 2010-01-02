class Triplicate
  module Coercion
    COERCIONS = {}
    COERCIONS[TrueClass]      = lambda{|v| Triplicate::Coercion.truthy?(v) }
    COERCIONS[FalseClass]     = lambda{|v| Triplicate::Coercion.truthy?(v) }
    COERCIONS[Fixnum]         = :to_i
    COERCIONS[Integer]        = :to_i
    COERCIONS[Float]          = :to_f
    COERCIONS[String]         = lambda do |v|
      v.respond_to?(:join) ? v.join(", ") : v.to_s
    end

    COERCIONS[Time]           = lambda do |v|
      if v.is_a?(Numeric)
        Time.at(v)
      elsif v.is_a?(String)
        begin
          Time.parse(v)
        rescue
          require 'time'
          retry
        end
      end
    end
    
    COERCIONS[Range]          = lambda do |v|
      raise unless v =~ /^(\d+|\d+\.\d+)(\.{2,3})(\d+|\d+\.\d+)$/
      start, middle, tail = $1, $2, $3
      start = start =~ /\./ ? start.to_f : start.to_i
      tail  = tail  =~ /\./ ? tail.to_f  : tail.to_i
      Range.new(start, tail, middle == "...")
    end
    
    SERIALIZATIONS = {}

    def self.coerce(value, klass)
      if klass.nil?
        value
      elsif value.kind_of?(klass)
        value
      elsif value.is_a?(Hash) && value.has_key?('json_class') && klass.responds_to?(:json_create)
        klass.json_create(value)
      elsif conversion = COERCIONS[klass]
        case conversion
        when Proc
          conversion.call(value)
        when Symbol
          value.send conversion
        end
      else
        klass.new(value)
      end
    end
    
    def self.serialize(value, klass)
      if serializer = (SERIALIZATIONS[klass] || SERIALIZATIONS[value.class])
        case serializer
        when Proc
          serializer.call(value)
        when Symbol
          value.send serializer
        end
      else
        value
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
end