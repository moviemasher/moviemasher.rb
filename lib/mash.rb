module MovieMasher
# Input#source of mash inputs, representing a collection #media arranged on #audio and #video tracks. 
#
# 
	class Mash
		include Hashable
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
		def self.hash? hash
			isa = false
			if hash.is_a?(Hash) or hash.is_a?(Mash)
				medias = __prop_for_ob(:media, hash)
				if medias and medias.is_a?(Array) then
					video_tracks = __prop_for_ob(:video, hash)
					audio_tracks = __prop_for_ob(:audio, hash)
					isa = (video_tracks or audio_tracks)
					# TODO: go further in verifying structure?
				end
			end
			isa
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
		def self.__media_reference mash, media_id, referenced, type = nil
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
			if sym and ob and (ob.is_a?(Hash) or ob.is_a?(Mash))
				sym = sym.to_sym unless sym.is_a? Symbol
				prop = ob[sym] || ob[sym.id2name]
			end
			prop
		end
		public
# Array - One or more Track objects. 
		def audio; _get __method__; end
# Array - One or more Media objects. 
		def media; _get __method__; end
# Array - One or more Track objects. 
		def video; _get __method__; end


	end
end


