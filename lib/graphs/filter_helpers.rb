module MovieMasher
  # helpers used by filter objects
  module FilterHelpers
    def self.mm_textfile(param_string, _mash, scope)
      job = scope[:mm_job]
      output = scope[:mm_output]
      path = Path.concat(job.output_path(output), "#{SecureRandom.uuid}.txt")
      params = __params_from_str(param_string)
      output[:commands] << { content: params.join(','), file: path }
      path
    end
    def self.rgb(param_string, _mash = nil, _scope = nil)
      params = __params_from_str(param_string)
      format('0x%02x%02x%02x', *params)
    end
    def self.rgba(param_string, _mash = nil, _scope = nil)
      params = __params_from_str(param_string)
      alpha = params.pop.to_f
      result = format('0x%02x%02x%02x', *params)
      result = "#{result}@#{alpha}"
      result
    end
    def self.mm_fontfile(param_string, mash, _scope)
      params = __params_from_str(param_string)
      font_id = params.join ','
      font = __find_font(font_id, mash)
      unless font[:cached_file]
        raise(Error::JobInput, "font has not been cached #{font}")
      end
      font[:cached_file]
    end
    def self.mm_fontfamily(param_string, mash, _scope)
      params = __params_from_str(param_string)
      font_id = params.join(',')
      font = __find_font(font_id, mash)
      raise(Error::JobInput, 'font has no family') unless font[:family]
      font[:family]
    end
    def self.mm_horz(param_string, mash = nil, scope = nil)
      __horz_vert(:mm_width, param_string, mash, scope)
    end
    def self.mm_vert(param_string, mash = nil, scope = nil)
      __horz_vert(:mm_height, param_string, mash, scope)
    end
    def self.mm_dir_horz(param_string, _mash, _scope)
      if param_string.empty?
        raise(Error::JobInput, "mm_dir_horz no parameters #{param_string}")
      end
      params = __params_from_str(param_string)
      # puts "mm_dir_horz #{param_string}} #{params.join ','}"
      case params[0].to_i # direction value
      when 0, 2 # center with no change
        '((in_w-out_w)/2)'
      when 1, 4, 5
        "((#{params[2]}-#{params[1]})*#{params[3]})"
      when 3, 6, 7
        "((#{params[1]}-#{params[2]})*#{params[3]})"
      else
        raise(Error::JobInput, "unknown direction #{params[0]}")
      end
    end
    def self.mm_paren(param_string, _mash, _scope)
      params = __params_from_str(param_string)
      "(#{params.join ','})"
    end
    def self.mm_dir_vert(param_string, _mash, _scope)
      if param_string.empty?
        raise(Error::JobInput, "mm_dir_vert no parameters #{param_string}")
      end
      params = __params_from_str(param_string)
      # puts "mm_dir_vert #{param_string} #{params.join ','}"
      result =
        case params[0].to_i # direction value
        when 1, 3 # center with no change
          '((in_h-out_h)/2)'
        when 0, 4, 7
          "((#{params[1]}-#{params[2]})*#{params[3]})"
        when 2, 5, 6
          "((#{params[2]}-#{params[1]})*#{params[3]})"
        else
          raise(Error::JobInput, "unknown direction #{params[0]}")
        end
      result
    end
    def self.mm_max(param_string, mash, scope)
      __max_min(:max, param_string, mash, scope)
    end
    def self.mm_min(param_string, mash, scope)
      __max_min(:min, param_string, mash, scope)
    end
    def self.mm_cmp(param_string, _mash, _scope)
      params = __params_from_str(param_string)
      param_0 = Evaluate.equation(params[0], true)
      param_1 = Evaluate.equation(params[0], true)
      (param_0 > param_1 ? params[2] : params[3])
    end
    def self.__find_font(font_id, mash)
      font = Mash.media_search(Type::FONT, font_id, mash)
      raise(Error::JobInput, "no font with id #{font_id} #{mash}") unless font
      font
    end
    def self.__horz_vert(w_h, param_string, _mash, scope)
      params = __params_from_str(param_string)
      value = params.shift
      proud = params.shift
      param_sym = value.to_sym
      value = scope[param_sym] if scope[param_sym]
      value = Evaluate.equation value
      if value.respond_to?(:round)
        w_h_value = scope[w_h].to_f
        if proud
          h_w = (:mm_height == w_h ? :mm_width : :mm_height)
          h_w_value = scope[h_w].to_f
          w_h_max = [w_h_value, h_w_value].max
          w_h_value_scaled = w_h_value + (value - 1.0) * w_h_max
        else
          w_h_value_scaled = w_h_value * value
        end
        result = w_h_value_scaled.round.to_i.to_s
      else
        result = "(#{scope[symbol]}*#{value})"
      end
      result
    end
    def self.__max_min(symbol, param_string, _mash, _scope)
      params = __params_from_str(param_string)
      all_ints = true
      evaluated_all = true
      params.map! do |p|
        p = Evaluate.equation p
        if p.respond_to? :round
          all_ints = false if all_ints && !FloatUtil.cmp(p.floor, p)
        else
          evaluated_all = false
        end
        p
      end
      if evaluated_all
        p = params.send symbol
        p = p.to_i if all_ints
      else
        p = "#{symbol.id2name}(#{params.join ','})"
      end
      p
    end
    def self.__params_from_str(param_string)
      param_string = param_string.split(',') if param_string.is_a?(String)
      param_string.map! { |p| p.is_a?(String) ? p.strip : p }
      param_string
    end
  end
end
