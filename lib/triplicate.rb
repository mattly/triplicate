require 'forwardable'
require 'ostruct'
class Triplicate < Hash
  extend Forwardable
  
  %w(coercion field).each do |req|
    mod = req.split(/[-_]/).map{|w|w.capitalize}.join
    autoload mod, "lib/triplicate/#{req}"
  end
  
  BUILTIN_VALIDATIONS = [:in, :not_in, :match, :satisfy].freeze
  
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
      
      fields[key.to_s] = Field.new(opts.update({:name => key.to_s, :parent => self}))
    end
  end
  
  def self.fields
    @fields ||= Hash.new {|h,k| k == k.to_s ? Field.new : h[k.to_s] }
  end
  
  def initialize(doc={})
    @document = doc || {}
    without_caching_document { @document.each {|key, value| self[key] = value } }
    fields.each do |name, field|
      next if @document.keys.include?(name)
      self[name] = field.collection.new if field.collection
    end
  end
  
  def_delegators :"self.class", :fields
  
  def [](key)
    key = key.to_s
    if fields[key].readable?
      cached_value(key, true)
      if super(key).nil? && !without_caching_document
        if set_default(key) then super(key)
        else fields[key].placeholder_for(self) end
      else
        super(key)
      end
    end
  end
  
  def []=(key, value)
    if fields[key].writeable? and ! without_writing
      if self[key].is_a?(Triplicate)
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
    without_caching_document do
      fields.each do |name, field|
        coerced = field.coerce(self[name])
        self[name] = coerced unless self[name] == coerced
        next if key?(name)
        set_default(name) if field.default
      end
    end
    valid?
  end
  
  def update(other, &block)
    without_caching_document do
      other.each do |key, value|
        if key?(key.to_s) && block_given?
          value = block.call(key, self[key], value)
        end
        self[key] = value
      end
    end
    self
  end
  
  def to_ostruct
    OpenStruct.new(self)
  end
    
  def valid?(key=nil)
    if key
      fields[key].valid_value?(self[key], self)
    else
      all? {|key, value| valid?(key) }
    end
  end
  
  def _cache_document
    return if without_caching_document
    @cached_document = @document.dup
  end
  
  def cached_value(key, force=false)
    return @document[key.to_s] if without_caching_document
    if force
      doc_value = @document[key.to_s]
      if doc_value != nil && doc_value != cached_value(key)
        _cache_document
        self[key] = doc_value
        self[key]
      end
    else
      @cached_document[key.to_s]
    end
  end
  
  def without_caching_document(&block)
    if block_given?
      begin
        _cache_document
        @without_caching_document = true
        yield
      ensure
        @without_caching_document = nil
        _cache_document
      end
    else
      @without_caching_document ||= nil
    end
  end
  
  def without_writing(&block)
    if block_given?
      begin
        @without_writing = true
        yield
      ensure 
        @without_writing = nil
      end
    else
      @without_writing ||= nil
    end
  end
  
  def set_default(key)
    value = fields[key].default_for(self)
    if !value.nil?
      without_caching_document { self[key] = value }
    end
  end
  
end