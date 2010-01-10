class Triplicate
  class Field
    extend Forwardable
    attr_reader :name, :parent
    
    def initialize(opts={})
      @name = opts.delete(:name)
      @parent = opts.delete(:parent)
      opts[:collection] = Array if opts[:collection] == true
      @opts = OpenStruct.new(opts)
    end
    
    def_delegators :@opts, :readable?, :writeable?, :collection, :coercion, :placeholder, :default, :validations
    
    def default_for(doc)
      coerce(value_for(doc, default))
    end
    
    def placeholder_for(doc)
      value_for(doc, placeholder)
    end
    
    def value_for(doc, interpreter)
      case interpreter
      when Proc
        doc.to_ostruct.instance_eval(&interpreter)
      when Symbol
        value = nil
        doc.without_writing { value = doc.send interpreter }
        value
      else
        interpreter
      end
    end
    
    def coerce(value, collecting=false)
      if collection && ! collecting
        build_collection value, :coerce
      elsif !value.nil? || [TrueClass, FalseClass].include?(coercion)
        Triplicate::Coercion.coerce(value, coercion)
      else
        value
      end
    end
    
    def serialize(value, collecting=false)
      if collection && ! collecting
        build_collection value, :serialize
      else
        Triplicate::Coercion.serialize(value, coercion)
      end
    end
    
    def build_collection(value, meth)
      value = collection.new if value.nil?
      if collection.respond_to?(:ancestors) && collection.ancestors.include?(Hash)
        value = collection[value] unless value.is_a?(collection)
        value.each {|k,v| value[k] = send(meth, v, true) }
      else
        value = collection.new(value) unless value.is_a?(collection)
        Triplicate::Coercion.send meth, collection.new((value||[]).map{|v| send(meth, v, true)}), nil
      end
    end
    
    def valid_value?(value, doc=nil, collecting=false)
      if collection && ! collecting
        value.is_a?(collection)
        value.all? {|val| valid_value?(val, doc, true)}
      else
        validations.all? do |group|
          group.all? do |operation, target|
            # TODO: Move to its own class
            case operation
            when :in
              target.respond_to?(:include?) && target.include?(value)
            when :not_in
              target.respond_to?(:include?) && ! target.include?(value)
            when :match
              target.respond_to?(:match) && target.match(value.to_s)
            when :satisfy
              unless doc.respond_to?(:to_ostruct)
                raise ArgumentError, "determining validation for this field requires passing the form as the second arguement"
              end
              case target
              when Proc
                if target.arity == 2 || ! Object.instance_methods.include?("instance_exec")
                  target.call(value, doc.to_ostruct)
                else
                  doc.to_ostruct.instance_exec(value, &target)
                end
              when Symbol
                value = nil
                doc.without_writing { value = doc.send target, value }
                value
              end
            end
          end
        end
      end
    end
    
  end
end