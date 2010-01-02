class Triplicate < Hash
  autoload :Coercion, 'lib/coercion'
  
  BUILTIN_VALIDATIONS = [:in, :not_in, :match, :against].freeze
  
  def self.field(*keys, &block)
    opts = keys.last.respond_to?(:has_key?) ? keys.pop : {}

    opts[:validate] = [opts[:validate]].flatten.compact
    (opts.keys & BUILTIN_VALIDATIONS).each do |validation|
      opts[:validate].push({validation => opts.delete(validation)})
    end

    [keys].flatten.each do |key|
      if block_given?
        klass = const_set(key.to_s.split('_').map{|s| s.capitalize }.join, Class.new(Triplicate))
        klass.class_eval &block
        opts[:coerce] = klass
      end
      
      fields[key.to_s] = {
        :read => true,
        :write => true
      }.update(opts)
    end
  end
  
  def self.fields
    @fields ||= Hash.new{|hash, key| hash[key] = {} }
  end
  
  def initialize(doc={})
    @document = doc
    _cache_document
    @document.each {|key, value| self[key.to_s] = value }
    self.class.fields.each do |name, opts|
      next if @document.keys.include?(name)
      self[name] = [] if opts[:collection]
    end
  end
  
  def [](key)
    key = key.to_s
    if readable?(key)
      _cached(key, true)
      if super(key).nil?
        if _set_default(key) then super(key)
        else _value_or_exec(field(key)[:placeholder]) end
      else
        super(key)
      end
    end
  end
  
  def []=(key, value)
    if writeable?(key)
      if !_raw and self[key].is_a?(Triplicate)
        self[key].update(value)
      else
        value = coerce(key, value)
        super(key.to_s, value)
        if value.is_a?(Triplicate)
          if @document[key.to_s].nil?
            @document[key.to_s] = value.instance_variable_get(:@document)
          end
        else
          @document[key.to_s] = serialize(key, value)
        end
      end
      _cache_document
    end
  end
  
  def process!
    each do |key, value|
      if self[key] != coerce(key, value)
        self[key] = coerce(key, value)
      end
    end
    self.class.fields.each do |name, opts|
      next if key?(name)
      _set_default(name) if opts[:default]
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
    begin
      OpenStruct.new(self)
    rescue NameError
      require 'ostruct'
      retry
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
  
  def collection?(key)
    field(key)[:collection]
  end
  
  def coercion(key)
    field(key)[:coerce]
  end
  
  def coerce(key, value, collecting=false)
    if collection?(key) && ! collecting
      value = [value] unless value.respond_to?(:each)
      a = _build_collection key, value, :coerce
    else
      Triplicate::Coercion.coerce(value, coercion(key))
    end
  end
  
  def serialize(key, value, collecting=false)
    if collection?(key) && ! collecting
      value = [value] unless value.respond_to?(:each)
      _build_collection key, value, :serialize
    else
      Triplicate::Coercion.serialize(value, coercion(key))
    end
  end
  
  def _build_collection(key, value, meth)
    if collection?(key).ancestors.include?(Hash)
      value.each {|k,v| value[k] = send(meth, key, v, true) }
    elsif collection?(key).is_a?(Class)
      send(meth, nil, collection?(key).new(value.map{|v| send(meth, key, v, true) }), true)
    else
      value.map {|val| send(meth, key, val, true) }
    end
  end
  
  def validations(key)
    field(key)[:validate]
  end
  
  def valid?(key=nil)
    if key
      value = self[key]
      if collection?(key)
        value.all? {|val| valid_value?(key, val) }
      else
        valid_value?(key, value)
      end
    else
      all? {|key, value| valid?(key) }
    end
  end
  
  def valid_value?(key, value)
    validations(key).all? do |set|
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
    @cached_document = @document.dup
  end
  
  def _cached(key, force=false)
    if force
      doc_value = @document[key]
      if doc_value != nil && doc_value != _cached(key)
        _cache_document
        _raw { self[key] = doc_value }
        self[key]
      end
    else
      @cached_document[key.to_s]
    end
  end
  
  def _raw(&block)
    if block_given?
      @raw_access = true
      yield
      @raw_access = nil
    else
      @raw_access || nil
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
    value = _value_or_exec field(key)[:default]
    if value = coerce(key, value)
      @document[key] = serialize(key, value)
      _cached(key, true)
    end
  end
  
end