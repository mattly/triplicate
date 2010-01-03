class Triplicate
  class Field
    
    class Declaration
      extend Forwardable
      attr_reader :name, :parent
      
      def initialize(opts={})
        @name = opts.delete(:name)
        @parent = opts.delete(:parent)
        if opts[:collection] == true
          opts[:collection] = Array
        end
        @opts = OpenStruct.new(opts)
      end
      
      def_delegators :@opts, :readable?, :writeable?, :collection, :coercion, :placeholder, :default, :validations
      
      def coerce(value, collecting=false)
        if collection && ! collecting
          build_collection value, :coerce
        else
          Triplicate::Coercion.coerce(value, coercion)
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
            
    end
  end
end