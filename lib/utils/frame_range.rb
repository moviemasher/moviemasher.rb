module MovieMasher
	class FrameRange < FrameTime
		def self.from_times(start_time, stop_time)
			start_time.synchronize stop_time
			FrameRange.new(start_time.frame, stop_time.frame - start_time.frame, start_time.fps)
		end
		def length
			@length
		end
		def length= n
			@length = n
		end
		def initialize (start = 0, length = 1, rate = 0)
			@length = length.to_i
			super(start, rate)
		end
		def length_time
			FrameTime.new(length, fps)
		end
		def end_time
			FrameTime.new(get_end, fps)
		 end
		def scale(rate, rounding = :round) # void
			if 0 < rate and fps != rate then
				if 0 < fps then
					floated = length.to_f / (fps.to_f / rate.to_f)
					floated = floated.send(rounding) if (rounding) 
					length = [1, floated].max
				end
				super rate, rounding
			end
		end
		def max_length time
			synchronize(time)
			@length = [time.frame, @length].max
		end
		def max_end time
			synchronize(time)
			set_end [time.get_end, get_end].max
		end
		def min_length time
			synchronize(time)
			@length = [time.frame, @length].min
		end
		def set_end n
			length = [1, (n.to_f - frame.to_f).to_i].max
		 end
		def get_end
			frame + length
		end
		def copy_time_range
			FrameRange.new @frame, @length, @fps
		end
		def intersection range
			result = nil
			range1 = self
			range2 = range
			if range1.fps != range2.fps then
				range1 = range1.copy_time_range
				range2 = range2.copy_time_range
				range1.synchronize range2
			end
			last_start = [range1.frame, range2.frame].max
			first_end = [range1.get_end, range2.get_end].min
			if (last_start < first_end) then
				result = FrameRange.new(last_start, first_end - last_start, range1.fps)
			end
			result
		end
		def is_equal_to_time_range? range
			equal = false
			if range and range.valid? then
				if (fps == range.fps) 
					equal = ((frame == range.frame) and (length == range.length))
				else
					# make copies so neither range is changed
					range1 = copy_time_range
					range2 = range.copy_time_range
					range1.synchronize range2
					equal = ((range1.frame == range2.frame) and (range1.length == range2.length))
				end
			end
			equal
		end
		def description
			"[FrameRange #{frame}+#{length}=#{get_end}@#{fps}]"
		end	
	end	
end
