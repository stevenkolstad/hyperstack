require 'active_support/core_ext/string'
module Hyperstack
  module Internal
    module Component
      class PropsWrapper
        attr_reader :component

        class << self
          def instance_var_name_for(name)
            case Hyperstack.naming_convention
            when :camelize_params
              name.camelize
            when :prefix_params
              "_#{name}"
            else
              name
            end
          end

          def param_accessor_style(style = nil)
            @param_accessor_style = style if style
            @param_accessor_style ||=
              if superclass.respond_to? :param_accessor_style
                superclass.param_accessor_style
              else
                :hyperstack
              end
          end

          def param_definitions
            @param_definitions ||=
              if superclass.respond_to? :param_definitions
                superclass.param_definitions.dup
              else
                Hash.new
              end
          end

          def define_param(name, param_type, aka = nil)
            meth_name = aka || name
            var_name = aka || instance_var_name_for(name)
            param_definitions[name] = lambda do |props|
              @component.instance_variable_set :"@#{var_name}", fetch_from_cache(name, param_type, props)
            end
            return if param_accessor_style == :hyperstack
            if param_type == Proc
              define_method(meth_name.to_sym) do |*args, &block|
                props[name].call(*args, &block) if props[name]
              end
            else
              define_method(meth_name.to_sym) do
                fetch_from_cache(name, param_type, props)
              end
            end
          end

          def define_all_others(name)
            var_name = instance_var_name_for(name)
            param_definitions[name] = lambda do |props|
              @component.instance_variable_set :"@#{var_name}", yield(props)
            end
            define_method(name.to_sym) do
              @_all_others_cache ||= yield(props)
            end
          end
        end

        def param_accessor_style
          self.class.param_accessor_style
        end

        def initialize(component, incoming = nil)
          @component = component
          return if param_accessor_style == :legacy
          self.class.param_definitions.each_value do |initializer|
            instance_exec(incoming || props, &initializer)
          end
        end

        def reload(next_props)
          @_all_others_cache = nil # needed for legacy params wrapper
          initialize(@component, next_props)
        end

        def [](prop)
          props[prop]
        end

        private

        def fetch_from_cache(name, param_type, props)
          last, cached_value = cache[name]
          return cached_value if last.equal?(props[name])
          convert_param(name, param_type, props).tap do |value|
            cache[name] = [props[name], value]
          end
        end

        def convert_param(name, param_type, props)
          if param_type.respond_to? :_react_param_conversion
            param_type._react_param_conversion props[name], nil
          elsif param_type.is_a?(Array) &&
                param_type[0].respond_to?(:_react_param_conversion)
            props[name].collect do |param|
              param_type[0]._react_param_conversion param, nil
            end
          else
            props[name]
          end
        end

        def cache
          @cache ||= Hash.new { |h, k| h[k] = [] }
        end

        def props
          component.props
        end

        def value_for(name)
          self[name].instance_variable_get('@value') if self[name]
        end
      end
    end
  end
end
