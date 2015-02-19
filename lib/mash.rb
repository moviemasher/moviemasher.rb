module MovieMasher
# Input#source of mash inputs, representing a collection #media arranged on #audio and #video tracks. 
#
# 
	class Mash < Hashable
		Audio = 'audio'
		Effect = 'effect'
		Font = 'font'
		Frame = 'frame'
		Image = 'image'
		Merger = 'merger'
		Scaler = 'scaler'
		Theme = 'theme'
		Tracks = ['audio', 'video']
		Transition = 'transition'
		Video = 'video'

		def self.clip_has_audio clip
			has = false
			unless clip[:no_audio]
				url = nil
				case clip[:type]
				when Mash::Audio
					url = (clip[:source] ? clip[:source] : clip[:audio])
				when Mash::Video
					url = (clip[:source] ? clip[:source] : clip[:audio]) unless 0 == clip[:audio]
				end
				if url
					has = ! clip[:gain]
					has = ! __gain_mutes(clip[:gain]) unless has
				end
			end
			#puts "clip_has_audio #{has} for #{clip[:label]} no_audio: #{clip[:no_audio]} no_video: #{clip[:no_video]}"
			has
		end
		def self.clips_having_audio mash
			clips = Array.new
			Mash::Tracks.each do |track_type|
				mash[track_type.to_sym].each do |track|
					track[:clips].each do |clip|
						clips << clip if clip_has_audio(clip)
					end
				end
			end
			clips
		end
		def self.clips_in_range mash, range, track_type
			clips_in_range = Array.new		
			mash[track_type.to_sym].each do |track|
				track[:clips].each do |clip|
					clips_in_range << clip if range.intersection(clip[:range]) 
				end
			end
			clips_in_range.sort! { |a,b| ((a[:track] == b[:track]) ? (a[:frame] <=> b[:frame]) : (a[:track] <=> b[:track]))}
			clips_in_range
		end
		def self.duration mash
			mash[:length] / mash[:quantize]
		end
		def self.gain_changes gain
			does = false;
			if gain.is_a?(String) and gain.include?(',') then
				gains = gain.split ','
				(gains.length / 2).times do |i|
					does = ! FloatUtil.cmp(gains[1 + i * 2].to_f, Gain::None)
					break if does
				end
			else
				does = ! FloatUtil.cmp(gain.to_f, Gain::None)
			end
			does
		end
		def self.hash? hash
			isa = false
			if hash.is_a?(Hash) or hash.is_a?(Mash)
				medias = __prop_for_ob(:media, hash)
				if medias and medias.is_a?(Array) then
					video_tracks = __prop_for_ob(:video, hash)
					audio_tracks = __prop_for_ob(:audio, hash)
					isa = (video_tracks or audio_tracks)
				end
			end
			isa
		end
		def self.has_audio? mash
			Mash::Tracks.each do |track_type|
				mash[track_type.to_sym].each do |track|
					track[:clips].each do |clip|
						return true if clip_has_audio clip
					end
				end
			end
			false
		end
		def self.has_video? mash
			Mash::Tracks.each do |track_type|
				next if Mash::Audio == track_type
				mash[track_type.to_sym].each do |track|
					track[:clips].each do |clip|
						return true
					end
				end
			end
			false
		end
		def self.init_hash mash
			Hashable._init_key mash, :backcolor, 'black'
			mash[:quantize] = (mash[:quantize] ? mash[:quantize].to_f : FloatUtil::One)
			mash[:media] = Array.new unless mash[:media] and mash[:media].is_a? Array
			longest = FloatUtil::Zero
			Mash::Tracks.each do |track_type|
				track_sym = track_type.to_sym
				mash[track_sym] = Array.new unless mash[track_sym] and mash[track_sym].is_a? Array
				mash[track_sym].length.times do |track_index|
					track = mash[track_sym][track_index]
					track[:clips] = Array.new unless track[:clips] and track[:clips].is_a? Array
					track[:clips].map! do |clip|
						clip = __init_clip clip, mash, track_index, track_type
						__init_clip_media(clip[:merger], mash, :merger) if clip[:merger]
						__init_clip_media(clip[:scaler], mash, :scaler) if clip[:scaler]
						clip[:effects].each do |effect|
							__init_clip_media effect, mash, :effect
						end
						clip
					end
					clip = track[:clips].last
					if clip then
						longest = FloatUtil.max(longest, clip[:range].stop)
					end
					track_index += 1
				end
			end
			mash[:length] = longest
			mash
		end
		def self.init_av_input input
			input[:av] = (input[:no_video] ? (input[:no_audio] ? AV::Neither : AV::Audio) : (input[:no_audio] ? AV::Video : AV::Both))
		end
		def self.init_input input
			input_type = input[:type]
			is_av = [Mash::Video, Mash::Audio].include? input_type
			is_v = [Mash::Video, Mash::Image, Mash::Frame].include? input_type
			
			input[:effects] = Array.new unless input[:effects] and input[:effects].is_a? Array
			input[:merger] = Defaults.module_for_type(:merger) unless input[:merger]
			input[:scaler] = Defaults.module_for_type(:scaler) unless input[:scaler] or input[:fill]
	
			# set volume with default of none (no adjustment)
			Hashable._init_key(input, :gain, Gain::None) if is_av
			Hashable._init_key(input, :fill, Fill::Stretch) if is_v
		
			# set source from url unless defined
			case input_type
			when Mash::Video, Mash::Image, Mash::Frame, Mash::Audio
				input[:source] = input[:url] unless input[:source]
				#input[:source] = Source.create(input[:source]) if input[:source].is_a?(Hash)
			end
			# set no_* when we know for sure
			case input_type
			when Input::TypeMash
				init_mash_input input
			when Input::TypeVideo
				input[:speed] = (input[:speed] ? input[:speed].to_f : FloatUtil::One) 
				input[:no_audio] = ! FloatUtil.cmp(FloatUtil::One, input[:speed])
				input[:no_video] = false
			when Input::TypeAudio
				Hashable._init_key input, :loop, 1
				input[:no_video] = true
			when Input::TypeImage
				input[:no_video] = false
				input[:no_audio] = true
			else
				input[:no_audio] = true
			end		
			input[:no_audio] = ! clip_has_audio(input) if is_av and not input[:no_audio]
			init_av_input input
		
		end
		def self.init_mash_input input
			if hash? input[:mash] then
				input[:mash] = Mash.new input[:mash]
				input[:mash].preflight if input[:mash]
				input[:duration] = duration(input[:mash]) if FloatUtil.cmp(input[:duration], FloatUtil::Zero)
				input[:no_audio] = ! has_audio?(input[:mash])
				input[:no_video] = ! has_video?(input[:mash])
			end
		end
		def self.media mash, ob_or_id
			if mash and ob_or_id
				ob_or_id = __prop_for_ob(:id, ob_or_id) if ob_or_id.is_a? Hash
				if ob_or_id
					media_array = __prop_for_ob(:media, mash)
					if media_array and media_array.is_a? Array
						media_array.each do |media|
							id = __prop_for_ob(:id, media)
							return media if id == ob_or_id
						end
					end
				end
			end
			nil
		end
		def self.media_count_for_clips mash, clips, referenced
			referenced = Hash.new unless referenced
			if clips
				clips.each do |clip|
					media_id = __prop_for_ob(:id, clip)
					__media_reference(mash, media_id, referenced)
					reference = referenced[media_id]
					if reference
						media = reference[:media]
						if media
							if __modular_media? media
								keys = __properties_for_media(media, Mash::Font)
								keys.each do |key|
									font_id = clip[key];
									__media_reference(mash, font_id, referenced, Mash::Font)
								end
							end
							media_type = __prop_for_ob(:type, media)
							case media_type
							when Mash::Transition
									__media_merger_scaler(mash, __prop_for_ob(:to, media), referenced)
									__media_merger_scaler(mash, __prop_for_ob(:from, media), referenced)
							when Mash::Effect, Mash::Audio
								# do nothing since clip has no effects, merger or scaler
							else
								__media_merger_scaler(mash, clip, referenced)
								media_count_for_clips(mash, __prop_for_ob(:effects, clip), referenced)
							end
						end
					else
						raise "__media_reference did not take note of #{media_id}"
					end
				end
			end
		end
		def self.media_search type, ob_or_id, mash
			media_ob = nil
			if ob_or_id
				ob_or_id = __prop_for_ob(:id, ob_or_id) if ob_or_id.is_a? Hash
				if ob_or_id
					media_ob = media(mash, ob_or_id) if mash
					media_ob = Defaults.module_for_type(type, ob_or_id) unless media_ob
				end
			end
			media_ob
		end
		def self.video_ranges mash
			quantize = mash[:quantize]
			frames = Array.new
			frames << 0
			frames << mash[:length]
			mash[:video].each do |track|
				track[:clips].each do |clip|
					frames << clip[:range].start
					frames << clip[:range].stop
				end
			end
			all_ranges = Array.new
			frames.uniq!
			frames.sort!
			frame_number = nil
			frames.length.times do |i|
				all_ranges << TimeRange.new(frame_number, quantize, frames[i] - frame_number) if frame_number
				frame_number = frames[i]
			end
			all_ranges
		end
		private
		def self.__gain_mutes gain
			does = true	
			if gain.is_a?(String) and gain.include?(',') then
				does = true
				gains = gain.split ','
				gains.length.times do |i|
					does = FloatUtil.cmp(gains[1 + i * 2].to_f, Gain::Mute)
					break unless does
				end
			else
				does = FloatUtil.cmp(gain.to_f, Gain::Mute)
			end
			does
		end
		def self.__media_merger_scaler mash, object, referenced
			if object
				merger = __prop_for_ob(Mash::Merger, object)
				if merger
					id = __prop_for_ob(:id, merger)
					__media_reference(mash, id, referenced, Mash::Merger) if id
				end
				scaler = __prop_for_ob(Mash::Scaler, object)
				if scaler
					id = __prop_for_ob(:id, scaler)
					__media_reference(mash, id, referenced, Mash::Scaler) if id
				end
			end
		end
		def self.__media_reference(mash, media_id, referenced, type = nil)
			if media_id and referenced
				if referenced[media_id]
					referenced[media_id][:count] += 1
				else
					referenced[media_id] = Hash.new
					referenced[media_id][:count] = 1
					referenced[media_id][:media] = media_search type, media_id, mash
				end
			end
		end
		def self.__modular_media? media
			case __prop_for_ob(:type, media)
			when Mash::Image, Mash::Audio, Mash::Video, Mash::Frame
				false
			else
				true
			end
		end
		def self.__properties_for_media media, type
			prop_keys = Array.new
			if type and media
				properties = __prop_for_ob(:properties, media)
				if properties and properties.is_a? Hash
					properties.each do |key, property|
					property_type = __prop_for_ob(:type, property)
					prop_keys << key if type == property_type
				end
			end
			end
			prop_keys
		end
		def self.__prop_for_ob sym, ob
			prop = nil
			if sym and ob and (ob.is_a?(Hash) or ob.is_a?(Hashable))
				sym = sym.to_sym unless sym.is_a? Symbol
				prop = ob[sym] || ob[sym.id2name]
			end
			prop
		end
		
		def self.__init_clip input, mash, track_index, track_type
			__init_clip_media input, mash
			input[:frame] = (input[:frame] ? input[:frame].to_f : FloatUtil::Zero)
			raise Error::JobInput.new "mash clips must have frames" unless input[:frames] and 0 < input[:frames]
			input[:range] = TimeRange.new input[:frame], mash[:quantize], input[:frames]
			input[:length] = input[:range].length_seconds unless input[:length]
			input[:track] = track_index if track_index 
			case input[:type]
			when Mash::Frame
				input[:still] = 0 unless input[:still]
				input[:fps] = mash[:quantize] unless input[:fps]
				if 2 > input[:still] + input[:fps] then
					input[:quantized_frame] = 0
				else 
					input[:quantized_frame] = mash[:quantize] * (input[:still].to_f / input[:fps].to_f).round
				end
			when Mash::Transition
				input[:to] = Hash.new unless input[:to]
				input[:from] = Hash.new unless input[:from]
				input[:to][:merger] = Defaults.module_for_type(:merger) unless input[:to][:merger]
				input[:to][:scaler] = Defaults.module_for_type(:scaler) unless input[:to][:scaler] or input[:to][:fill]
				input[:from][:merger] = Defaults.module_for_type(:merger) unless input[:from][:merger]
				input[:from][:scaler] = Defaults.module_for_type(:scaler) unless input[:from][:scaler] or input[:from][:fill]
				__init_clip_media(input[:to][:merger], mash, Mash::Merger)
				__init_clip_media(input[:from][:merger], mash, Mash::Merger)
				__init_clip_media(input[:to][:scaler], mash, Mash::Scaler)
				__init_clip_media(input[:from][:scaler], mash, Mash::Scaler)
			when Mash::Video, Mash::Audio
				input[:trim] = 0 unless input[:trim]
				input[:offset] = input[:trim].to_f / mash[:quantize] unless input[:offset]
			end
			init_input input
			Clip.create input
		end
		def self.__init_clip_media clip, mash, type = nil
			raise Error::JobInput.new "clip has no id #{clip}" unless clip[:id]
			media = media_search type, clip, mash
			raise Error::JobInput.new "#{clip[:id]} #{type ? type : 'media'} not found in mash" unless media
			media.each do |k,v|
				clip[k] = v unless clip[k]
			end 
		end



		public
# Array - One or more Track objects. 
		def audio
			_get __method__
		end
		def initialize hash
			super
			self.class.init_hash @hash
		end
# Array - One or more Media objects. 
		def media
			_get __method__
		end
		def preflight job = nil
			media.map! do |media|
				case media[:type]
				when Video, Audio, Image, Frame, Font
					media = Clip.create media
					media.preflight job
				end
				media
			end
		end
		def url_count desired
			count = 0
			media.each do |media|
				case media[:type]
				when Mash::Video, Mash::Audio, Mash::Image, Mash::Font
					if AV.includes?(Asset.av_type(media), desired) then
						count += 1 
					end
				end
			end
			count
		end
		
# Array - One or more Track objects. 
		def video
			_get __method__
		end


	end
end


