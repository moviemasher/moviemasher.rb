# frozen_string_literal: true

module MovieMasher
  # Base class for mocking a Hash.
  class Hashable
    class << self
      def resolved_hash(hash_or_path)
        data = {}
        case hash_or_path
        when String
          hash_or_path = __resolved_string(hash_or_path)
          if hash_or_path
            begin
              case __string_type(hash_or_path)
              when 'yaml'
                data = YAML.load(hash_or_path)
              when 'json'
                data = JSON.parse(hash_or_path)
              else
                data[:error] = "unsupported configuration type #{hash_or_path}"
              end
            rescue StandardError => e
              data[:error] = "job file could not be parsed: #{e.message}"
            end
          else
            data[:error] = "job file could not be found: #{hash_or_path}"
          end
        when Hash
          data = Marshal.load(Marshal.dump(hash_or_path))
        end
        symbolize(data)
      end

      def symbolize(hash_or_array, key = nil)
        result = hash_or_array
        case hash_or_array
        when Hash
          result = {}
          hash_or_array.each do |k, v|
            k = k.downcase if k.is_a?(String) && key != :parameters
            k = k.to_sym
            result[k] = symbolize(v, k)
          end
        when Array
          result = hash_or_array.map { |v| symbolize(v) }
        end
        result
      end

      protected

      def _init_key(hash, key, default)
        return unless hash

        value = hash[key]
        overwrite = value.nil?
        unless overwrite
          if default.is_a?(Array) || default.is_a?(Hash)
            overwrite = !(value.is_a?(Array) || value.is_a?(Hash))
            overwrite ||= value.empty?
          else
            overwrite = value.to_s.empty?
          end
        end
        hash[key] = default if overwrite
      end

      def _init_time(input, key)
        if input[key]
          rel_key = :"#{key.id2name}_is_relative"
          val_key = :"#{key.id2name}_relative_value"
          value = input[key].to_s
          if value.start_with?('-')
            input[val_key] = input[key].to_f
            input[rel_key] = '-'
          elsif value.end_with?('%')
            value['%'] = ''
            input[val_key] = value.to_f
            input[rel_key] = '%'
          else
            input[key] = value.to_f
          end
        else
          input[key] = FloatUtil::ZERO
        end
      end

      private

      def __resolved_string(hash_or_path)
        case __string_type(hash_or_path)
        when 'json', 'yaml'
          hash_or_path
        else
          (File.exist?(hash_or_path) ? File.read(hash_or_path) : nil)
        end
      end

      def __string_type(hash_or_path)
        case hash_or_path[0]
        when '{', '['
          'json'
        when '-'
          'yaml'
        end
      end
    end

    attr_accessor :hash, :identifier

    # Set the actual Hash when creating.
    def initialize(hash = nil)
      unless hash.is_a?(Hash)
        # puts "Hashable#initialize NOT HASH #{hash}"
        hash = {}
      end
      @hash = hash
      @identifier = SecureRandom.uuid
    end

    def keys
      @hash.keys
    end

    def slice(*keys)
      @hash.slice(*keys)
    end

    # Return deep copy of underlying Hash.
    def to_hash
      Marshal.load(Marshal.dump(@hash))
    end

    # Return underlying Hash in JSON format.
    def to_json(state = nil)
      @hash.to_json state
    end

    def to_s
      @hash.to_s
    end

    def values
      @hash.values
    end

    # Convenience getter for underlying data Hash.
    #
    # symbol - Symbol key into hash.
    #
    # Returns value of key or nil if no such key exists.
    def [](symbol)
      @hash[symbol]
    end

    # Convenience setter for underlying data Hash.
    #
    # symbol - Symbol key into hash.
    # value - Object to set at key.
    #
    # Returns *value*.
    def []=(symbol, value)
      @hash[symbol] = value
    end

    def _set(symbol, value)
      symbol = symbol.to_s[0..-2].to_sym
      @hash[symbol] = value
    end

    def _get(symbol)
      @hash[symbol]
    end
  end
end
