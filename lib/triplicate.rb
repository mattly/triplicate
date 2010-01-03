require 'forwardable'
require 'ostruct'
class Triplicate < Hash
  extend Forwardable
  
  %w(coercion field).each do |req|
    mod = req.split(/[-_]/).map{|w|w.capitalize}.join
    autoload mod, "lib/triplicate/#{req}"
  end
  
  BUILTIN_VALIDATIONS = [:in, :not_in, :match, :against].freeze
  
  def self.field(*keys, &block)
    opts = keys.last.respond_to?(:has_key?) ? keys.pop : {}
    
    opts[:validations] = [opts.delete(:validate)].flatten.compact
    (opts.keys & BUILTIN_VALIDATIONS).each do |validation|
      opts[:validations].push({validation => opts.delete(validation)})
    end
    opts[:coercion] = opts.delete(:coerce)
    opts.update({:readable? => true, :writeable? => true}) {|k,v1,v2| v1 }

    [keys].flatten.each do |key|
      if block_given?
        klass = const_set(key.to_s.split('_').map{|s| s.capitalize }.join, Class.new(Triplicate))
        klass.class_eval &block
        opts[:coercion] = klass
      end
      
      fields[key.to_s] = Field::Declaration.new(opts.update({:name => key.to_s, :parent => self}))
    end
  end
  
  def self.fields
    @fields ||= Hash.new {|h,k| k == k.to_s ? Field::Declaration.new : h[k.to_s] }
  end
  
  def initialize(doc={})
    @document = doc || {}
    _without_caching { @document.each {|key, value| self[key] = value } }
    _cache_document
    fields.each do |name, field|
      next if @document.keys.include?(name)
      self[name] = field.collection.new if field.collection
    end
  end
  
  def_delegators :"self.class", :fields
  
  def [](key)
    key = key.to_s
    if fields[key].readable?
      _cached(key, true)
      if super(key).nil? && !_without_caching
        if _set_default(key) then super(key)
        else _value_or_exec(fields[key].placeholder) end
      else
        super(key)
      end
    end
  end
  
  def []=(key, value)
    if fields[key].writeable?
      if !_without_caching and self[key].is_a?(Triplicate)
        self[key].update(value)
      else
        coerced = fields[key].coerce(value)
        super(key.to_s, coerced)
        if coerced.is_a?(Triplicate)
          if @document[key.to_s].nil?
            @document[key.to_s] = coerced.instance_variable_get(:@document)
          end
        else
          @document[key.to_s] = fields[key].serialize(coerced)
        end
      end
      _cache_document
    end
  end
  
  def process!
    fields.each do |name, field|
      coerced = field.coerce(self[name])
      self[name] = coerced unless self[name] == coerced
      next if key?(name)
      _set_default(name) if field.default
    end
  end
  
  def update(other, &block)
    other.each do |key, value|
      if key?(key.to_s) && block_given?
        value = block.call(key, self[key], value)
      end
      self[key] = value
    end
    self
  end
  
  def to_ostruct
    OpenStruct.new(self)
  end
    
  def valid?(key=nil)
    if key
      value = self[key]
      if fields[key].collection
        value.all? {|val| valid_value?(key, val) }
      else
        valid_value?(key, value)
      end
    else
      all? {|key, value| valid?(key) }
    end
  end
  
  def valid_value?(key, value)
    fields[key].validations.all? do |set|
      set.all? do |operation, target|
        case operation
        when :in
          target.respond_to?(:include?) && target.include?(value)
        when :not_in
          target.respond_to?(:include?) && ! target.include?(value)
        when :match
          target.respond_to?(:match) && target.match(value.to_s)
        when :against
          target.is_a?(Proc) && target.call(value, self)
        end
      end
    end
  end
  
  def _cache_document
    return if _without_caching
    @cached_document = @document.dup
  end
  
  def _cached(key, force=false)
    return @document[key.to_s] if _without_caching
    if force
      doc_value = @document[key.to_s]
      if doc_value != nil && doc_value != _cached(key)
        _cache_document
        self[key] = doc_value
        self[key]
      end
    else
      @cached_document[key.to_s]
    end
  end
  
  def _without_caching(&block)
    if block_given?
      @nocache = true
      yield
      @nocache = nil
    else
      @nocache ||= nil
    end
  end
  
  def _value_or_exec(thing)
    if thing.is_a?(Proc)
      to_ostruct.instance_eval(&thing)
    else
      thing
    end
  end
  
  def _set_default(key)
    value = _value_or_exec fields[key].default
    return if value.nil?
    if value = fields[key].coerce(value)
      @document[key] = fields[key].serialize(value)
      _cached(key, true)
    end
  end
  
end