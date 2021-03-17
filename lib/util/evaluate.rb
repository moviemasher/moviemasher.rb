# frozen_string_literal: true

require 'dentaku'

module MovieMasher
  # evaluates certain simple expressions
  module Evaluate
    class << self
      attr_accessor :__calculator

      def calculator
        Evaluate.__calculator ||= Dentaku::Calculator.new
      end

      def coerce_if_numeric(value)
        numeric?(value) || value
      end

      def coerce_number(value)
        integer?(value) || numeric?(value) || value
      end

      def equation(string, raise_on_fail = nil)
        # do_puts = string.to_s.include?('overlay')
        evaluated = string
        # change all numbers to floats
        fs = string.to_s.gsub(/([0-9]+[.]?[0-9]*)/, &:to_f)
        fs = "0 + (#{fs})"
        begin
          # puts "Evaluating: #{fs} #{fs.class.name}" if do_puts
          evaluated = calculator.evaluate!(fs)
          evaluated = evaluated.to_f if evaluated.is_a?(BigDecimal)
          # puts "Evaluated: #{evaluated} #{evaluated.class.name}" if do_puts
        rescue StandardError => e
          # puts "Evaluation Failed: #{evaluated} #{evaluated.class.name} #{fs} #{e.message}" if do_puts
          if raise_on_fail
            raise(Error::JobInput, "evaluation failed #{fs} #{e.message}")
          end
        end
        evaluated
      end

      def object(data, scope = nil)
        scope ||= {}
        keys = (data.is_a?(Array) ? (0..(data.length - 1)) : data.keys)
        keys.each do |k|
          v = data[k]
          if __is_eval_object?(v)
            object(v, scope) # recurse
          elsif v.is_a?(Proc)
            data[k] = v.call(scope)
          else
            data[k] = value(v.to_s, scope)
          end
        end
      end

      def numeric?(value)
        v_str = value.to_s
        return false if v_str.include?(' ')

        sym = (v_str.include?('.') ? :to_f : :to_i)
        v_num = v_str.send(sym)
        return false unless v_str == v_num.to_s

        v_num
      end

      def integer?(value)
        value_numeric = numeric?(value)
        return false unless value_numeric

        return false if value_numeric.abs < 1.0

        value_numeric.round.to_i        
      end

      def value(string, scope = nil)
        scope ||= {}
        split_value = __split(string)
        unless split_value.empty? # otherwise there are no curly braces
          string = ''
          is_static = true
          split_value.each do |bit|
            if is_static
              string += bit
            else
              split_bit = bit.split '.'
              child = __scope_target(split_bit, scope) # shifts off first
              evaled = nil
              evaled = __evaluated_scope_child(child, split_bit) if child
              string =
                if __is_eval_object?(evaled)
                  evaled
                elsif evaled.is_a?(Proc)
                  evaled.call
                else
                  "#{string}#{evaled}"
                end
            end
            is_static = !is_static
          end
        end
        string
      end

      private

      def __evaluated_scope_child(child, split_bit)
        if __is_eval_object?(child)
          __value(child, split_bit)
        elsif child.is_a?(Proc)
          child.call
        else
          child
        end
      end

      def __is_eval_object?(object)
        (object.is_a?(Hash) || object.is_a?(Array) || object.is_a?(Hashable))
      end

      def __scope_target(split_bit, scope)
        scope_child = nil
        until split_bit.empty?
          first_key = split_bit.shift
          scope_child = scope[first_key.to_sym]
          break if scope_child
        end
        scope_child
      end

      def __split(string)
        string.to_s.split(/{([^}]*)}/)
      end

      def __value(object, path_array)
        v = object
        key = path_array.shift
        if key
          key = (key.to_i.to_s == key ? key.to_i : key.to_sym)
          v = (key.is_a?(Symbol) && v.respond_to?(key) ? v.send(key) : v[key])
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
end
