module MovieMasher
  # default scaler, merger and font
  module Defaults
    SCALER_ID = 'com.moviemasher.scaler.default'.freeze
    MERGER_ID = 'com.moviemasher.merger.default'.freeze
    FONT_ID = 'com.moviemasher.font.default'.freeze
    def self.module_for_type(type, media_id = nil)
      type = __string(type)
      case type
      when Type::FONT
        __font_default unless media_id && FONT_ID != media_id
      when Type::MERGER
        __merger_default unless media_id && MERGER_ID != media_id
      when Type::SCALER
        __scaler_default unless media_id && SCALER_ID != media_id
      end
    end
    def self.__string(type)
      (type.respond_to?(:id2name) ? type.id2name : type)
    end
    def self.__font_default
      config = {}
      config[:id] = FONT_ID
      config[:type] = Type::FONT
      config[:source] = {}
      config[:source][:method] = Method::SYMLINK
      config[:source][:type] = Type::FILE
      config[:cached_file] = "#{File.dirname(__FILE__)}/../../config/font/"\
        'theleagueof-blackout/webfonts/blackout_two_am-webfont.ttf'
      config[:family] = 'Blackout Two AM'
      config
    end
    def self.__merger_default
      config = {}
      config[:id] = MERGER_ID
      config[:type] = Type::MERGER
      config[:filters] = []
      overlay_config = {}
      overlay_config[:id] = 'overlay'
      overlay_config[:parameters] = []
      overlay_config[:parameters] << { name: 'x', value: '0' }
      overlay_config[:parameters] << { name: 'y', value: '0' }
      config[:filters] << overlay_config
      config
    end
    def self.__scaler_default
      config = {}
      config[:id] = SCALER_ID
      config[:type] = Type::SCALER
      config[:filters] = []
      scale_config = {}
      scale_config[:id] = 'scale'
      scale_config[:parameters] = []
      scale_config[:parameters] << { name: 'width', value: 'mm_width' }
      scale_config[:parameters] << { name: 'height', value: 'mm_height' }
      config[:filters] << scale_config
      setsar_config = {}
      setsar_config[:id] = 'setsar'
      setsar_config[:parameters] = []
      setsar_config[:parameters] << { name: 'sar', value: '1' }
      setsar_config[:parameters] << { name: 'max', value: '1' }
      config[:filters] << setsar_config
      config
    end
  end
end
