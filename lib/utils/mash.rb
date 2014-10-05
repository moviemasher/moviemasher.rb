module MovieMasher
	module Mash
		FillNone = 'none'
		FillStretch = 'stretch'
		FillCrop = 'crop'
		FillScale = 'scale'
		VolumeNone = Float::One
		VolumeMute = Float::Zero
		
		def self.clip_has_audio clip
			has = false
			unless clip[:no_audio]
				url = nil
				case clip[:type]
				when Type::Audio
					url = (clip[:source] ? clip[:source] : clip[:audio])
				when Type::Video
					url = (clip[:source] ? clip[:source] : clip[:audio]) unless 0 == clip[:audio]
				end
				if url
					has = ! clip[:gain]
					has = ! gain_mutes(clip[:gain]) unless has
				end
			end
			#puts "clip_has_audio #{has} for #{clip[:label]} no_audio: #{clip[:no_audio]} no_video: #{clip[:no_video]}"
			has
		end
		def self.clips_having_audio mash
			clips = Array.new
			Type::Tracks.each do |track_type|
				mash[:tracks][track_type.to_sym].each do |track|
					track[:clips].each do |clip|
						clips << clip if clip_has_audio(clip)
					end
				end
			end
			clips
		end
		def self.clips_in_range mash, range, track_type
			clips_in_range = Array.new		
			mash[:tracks][track_type.to_sym].each do |track|
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
					does = ! Float.cmp(gains[1 + i * 2].to_f, VolumeNone)
					break if does
				end
			else
				does = ! Float.cmp(gain.to_f, VolumeNone)
			end
			does
		end
		def self.gain_mutes gain
			does = true	
			if gain.is_a?(String) and gain.include?(',') then
				does = true
				gains = gain.split ','
				gains.length.times do |i|
					does = Float.cmp(gains[1 + i * 2].to_f, VolumeMute)
					break unless does
				end
			else
				does = Float.cmp(gain.to_f, VolumeMute)
			end
			does
		end
		def self.has_audio? mash
			Type::Tracks.each do |track_type|
				mash[:tracks][track_type.to_sym].each do |track|
					track[:clips].each do |clip|
						return true if clip_has_audio clip
					end
				end
			end
			false
		end
		def self.has_video? mash
			Type::Tracks.each do |track_type|
				next if Type::TrackAudio == track_type
				mash[:tracks][track_type.to_sym].each do |track|
					track[:clips].each do |clip|
						return true
					end
				end
			end
			false
		end
		def self.media mash, ob_or_id
			if mash and ob_or_id
				ob_or_id = prop_for_ob(:id, ob_or_id) if ob_or_id.is_a? Hash
				if ob_or_id
					media_array = prop_for_ob(:media, mash)
					if media_array and media_array.is_a? Array
						media_array.each do |media|
							id = prop_for_ob(:id, media)
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
				ob_or_id = prop_for_ob(:id, ob_or_id) if ob_or_id.is_a? Hash
				if ob_or_id
					media_ob = media(mash, ob_or_id) if mash
					media_ob = Defaults.module_for_type(type, ob_or_id) unless media_ob
				else
					puts "not ob_or_id"
				end
			else
				puts "not type and ob_or_id "
			end
			media_ob
		end
		def self.hash? hash
			isa = false
			if hash.is_a?(Hash)
				medias = prop_for_ob(:media, hash)
				tracks = prop_for_ob(:tracks, hash)		
				if medias and tracks and medias.is_a?(Array) and tracks.is_a? Hash then
					video_tracks = prop_for_ob(:video, tracks)
					audio_tracks = prop_for_ob(:audio, tracks)
					isa = (video_tracks or audio_tracks)
					# todo: go further in verifying structure, allowing for
					# just audio or video tracks
				end
			end
			isa
		end
		def self.media_count_for_clips mash, clips, referenced
			referenced = Hash.new unless referenced
			if clips
				clips.each do |clip|
					media_id = prop_for_ob(:id, clip)
					media_reference(mash, media_id, referenced)
					reference = referenced[media_id]
					if reference
						media = reference[:media]
						if media
							if modular_media? media
								keys = properties_for_media(media, Type::Font)
								keys.each do |key|
									font_id = clip[key];
									media_reference(mash, font_id, referenced, Type::Font)
								end
							end
							media_type = prop_for_ob(:type, media)
							case media_type
							when Type::Transition
									media_merger_scaler(mash, prop_for_ob(:to, media), referenced)
									media_merger_scaler(mash, prop_for_ob(:from, media), referenced)
							when Type::Effect, Type::Audio
								# do nothing since clip has no effects, merger or scaler
							else
								media_merger_scaler(mash, clip, referenced)
								media_count_for_clips(mash, prop_for_ob(:effects, clip), referenced)
							end
						end
					else
						raise "media_reference did not take note of #{media_id}"
					end
				end
			end
		end
		def self.media_for_clips mash, clips
			medias = Array.new
			if mash and clips
				clips = [clips] unless clips.is_a? Array
				referenced = Hash.new
				media_count_for_clips(mash, clips, referenced)
				referenced.each do |k, v|
					medias << v[:media]
				end
			end
			medias
		end
		def self.media_merger_scaler mash, object, referenced
			if object
				merger = prop_for_ob(Type::Merger, object)
				if merger
					id = prop_for_ob(:id, merger)
					media_reference(mash, id, referenced, Type::Merger) if id
				end
				scaler = prop_for_ob(Type::Scaler, object)
				if scaler
					id = prop_for_ob(:id, scaler)
					media_reference(mash, id, referenced, Type::Scaler) if id
				end
			end
		end
		def self.media_reference mash, media_id, referenced, type = nil
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
		def self.modular_media? media
			case prop_for_ob(:type, media)
			when Type::Image, Type::Audio, Type::Video, Type::Frame
				false
			else
				true
			end
		end
		def self.properties_for_media media, type
			prop_keys = Array.new
			if type and media
				properties = prop_for_ob(:properties, media)
				if properties and properties.is_a? Hash
					properties.each do |key, property|
					property_type = prop_for_ob(:type, property)
					prop_keys << key if type == property_type
				end
			end
			end
			prop_keys
		end
		def self.prop_for_ob sym, ob
			prop = nil
			if sym and ob and ob.is_a? Hash
				sym = sym.to_sym unless sym.is_a? Symbol
				prop = ob[sym] || ob[sym.id2name]
			end
			prop
		end
		def self.video_ranges mash
			quantize = mash[:quantize]
			frames = Array.new
			frames << 0
			frames << mash[:length]
			mash[:tracks][:video].each do |track|
				track[:clips].each do |clip|
					frames << clip[:range].frame
					frames << clip[:range].get_end
				end
			end
			all_ranges = Array.new
			frames.uniq!
			frames.sort!
			frame = nil
			frames.length.times do |i|
				all_ranges << FrameRange.new(frame, frames[i] - frame, quantize) if frame
				frame = frames[i]
			end
			all_ranges
		end
	end
end


