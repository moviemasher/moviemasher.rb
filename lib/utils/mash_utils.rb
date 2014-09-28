module MovieMasher
	module Mash
		FillNone = 'none'
		FillStretch = 'stretch'
		FillCrop = 'crop'
		FillScale = 'scale'
		VolumeNone = Float::One
		VolumeMute = Float::Zero
		
		def self.clips_having_audio mash
			clips = Array.new
			Type::Tracks.each do |track_type|
				mash[:tracks][track_type.to_sym].each do |track|
					track[:clips].each do |clip|
						clips << clip unless clip[:no_audio] or not clip_has_audio(clip)
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
		def self.search(mash, id, key = :media)
			mash[key].each do |item|
				return item if id == item[:id]
			end
			nil
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
		def self.clip_has_audio clip
			has = false
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
			has
		end
		def self.hash? hash
			isa = false
			if hash.is_a?(Hash) and hash[:media] and hash[:media].is_a?(Array) then
				if hash[:tracks] and hash[:tracks].is_a? Hash then
					if hash[:tracks][:video] and hash[:tracks][:video].is_a? Array then
						isa = true
					end
				end
			end
			isa
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
	end
end


