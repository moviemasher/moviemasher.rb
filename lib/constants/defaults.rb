module MovieMasher
	module Defaults
		ScalerID = 'com.moviemasher.scaler.default'
		MergerID = 'com.moviemasher.merger.default'
		FontID = 'com.moviemasher.font.default'
		def self.__font_default
			config = Hash.new
			config[:id] = FontID
			config[:type] = Type::Font
			config[:source] = Hash.new
			config[:source][:method] = Method::Symlink
			config[:source][:type] = Type::File
			config[:cached_file] = "#{__dir__}/../../config/font/theleagueof-blackout/webfonts/blackout_two_am-webfont.ttf"
			config[:family] = "Blackout Two AM"
			config
		end
		def self.__merger_default
			config = Hash.new
			config[:id] = MergerID
			config[:type] = Type::Merger
			config[:filters] = Array.new
			overlay_config = Hash.new
			overlay_config[:id] = 'overlay'
			overlay_config[:parameters] = Array.new
			overlay_config[:parameters] << {:name => 'x', :value => '0'}
			overlay_config[:parameters] << {:name => 'y', :value => '0'}
			config[:filters] << overlay_config
			config
		end
		def self.__scaler_default
			config = Hash.new
			config[:id] = ScalerID
			config[:type] = Type::Scaler
			config[:filters] = Array.new
			scale_config = Hash.new
			scale_config[:id] = 'scale'
			scale_config[:parameters] = Array.new
			scale_config[:parameters] << {:name => 'width', :value => 'mm_width'}
			scale_config[:parameters] << {:name => 'height', :value => 'mm_height'}
			config[:filters] << scale_config
			config
		end
		def self.module_for_type type, media_id = nil
			case type
			when Type::Font, Type::Font.to_sym
				__font_default unless media_id and FontID != media_id
			when Type::Merger, Type::Merger.to_sym
				__merger_default unless media_id and MergerID != media_id
			when Type::Scaler, Type::Scaler.to_sym
				__scaler_default unless media_id and ScalerID != media_id
			end
		end
	end
end
