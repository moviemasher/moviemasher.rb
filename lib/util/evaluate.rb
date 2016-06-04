
require 'dentaku'

module MovieMasher
  # evaluates certain simple expressions
  module Evaluate
    class << self
      attr_accessor :__calculator
    end
    Evaluate.__calculator = nil
    def self.calculator
      Evaluate.__calculator ||= Dentaku::Calculator.new
    end
    def self.coerce_if_numeric(value)
      v_str = value.to_s
      unless v_str.include?(' ')
        sym = (v_str.include?('.') ? :to_f : :to_i)
        value = value.send(sym) if v_str == v_str.send(sym).to_s
      end
      value
    end
    def self.equation(s, raise_on_fail = nil)
      evaluated = s
      # change all numbers to floats
      fs = s.to_s.gsub(/([0-9]+[.]?[0-9]*)/, &:to_f)
      fs = "0 + (#{fs})"
      begin
        # puts "Evaluating: #{fs} #{fs.class.name}"
        evaluated = calculator.evaluate!(fs)
        evaluated = evaluated.to_f if evaluated.is_a?(BigDecimal)
        # puts "Evaluated: #{evaluated} #{evaluated.class.name}"
      rescue => e
        if raise_on_fail
          raise(Error::JobInput, "evaluation failed #{fs} #{e.message}")
        end
      end
      evaluated
    end
    def self.object(data, scope = nil)
      scope = {} unless scope
      keys = (data.is_a?(Array) ? (0..(data.length - 1)) : data.keys)
      keys.each do |k|
        v = data[k]
        if __is_eval_object?(v)
          object(v, scope) # recurse
        elsif v.is_a?(Proc)
          data[k] = v.call
        else
          data[k] = value(v.to_s, scope)
        end
      end
    end
    def self.value(v, scope)
      split_value = __split(v)
      unless split_value.empty? # otherwise there are no curly braces
        v = ''
        is_static = true
        split_value.each do |bit|
          if is_static
            v += bit
          else
            split_bit = bit.split '.'
            child = __scope_target(split_bit, scope) # shifts off first
            evaled = nil
            evaled = __evaluated_scope_child(child, split_bit) if child
            v =
              if __is_eval_object?(evaled)
                evaled
              elsif evaled.is_a?(Proc)
                evaled.call
              else
                "#{v}#{evaled}"
              end
          end
          is_static = !is_static
        end
      end
      v
    end
    def self.__evaluated_scope_child(child, split_bit)
      if __is_eval_object?(child)
        __value(child, split_bit)
      elsif child.is_a?(Proc)
        child.call
      else
        child
      end
    end
    def self.__is_eval_object?(ob)
      (ob.is_a?(Hash) || ob.is_a?(Array) || ob.is_a?(Hashable))
    end
    def self.__scope_target(split_bit, scope)
      scope_child = nil
      until split_bit.empty?
        first_key = split_bit.shift
        scope_child = scope[first_key.to_sym]
        break if scope_child
      end
      scope_child
    end
    def self.__split(s)
      s.to_s.split(/{([^}]*)}/)
    end
    def self.__value(ob, path_array)
      v = ob
      key = path_array.shift
      if key
        key = (key.to_i.to_s == key ? key.to_i : key.to_sym)
        v = ((key.is_a?(Symbol) && v.respond_to?(key)) ? v.send(key) : v[key])
        if __is_eval_object? v
          v = __value(v, path_array) unless path_array.empty?
        elsif v.is_a?(Proc)
          v = v.call
        else
          v = v.to_s
        end
      end
      v
    end
  end
end
