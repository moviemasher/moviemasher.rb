
module MovieMasher
	class FrameTime
		def self.from_seconds(seconds = 0, rate = 0, rounding = :round)
			FrameTime.new((seconds.to_f * rate.to_f).send(rounding).to_i, rate)
		end
		def add time
			synchronize time
			@frame += time.frame
		end
		def copy_time
			FrameTime.new(@frame, @fps)	
		end
		def description
			"[FrameTime #{frame}@#{fps}]"
		end	
		def divide(number, rounding = :round)
			number = number.to_f if number.respond_to? :to_f
			@frame = (@frame.to_f / number).send(rounding)
		end
		def fps
			@fps
		end
		def frame= new_frame
			@frame = new_frame
		end
		def frame
			@frame
		end
		def frame_for_rate(rate, rounding = :round)
			start = @frame
			if rate != @fps then
				start = FrameTime.from_seconds(get_seconds, @fps, rounding).frame
			end
			start	
		end
		def get_seconds precision = 3
			Float.precision((@frame.to_f / @fps.to_f), precision)
		end
		def get_time_range
			FrameRange.new(@frame, 1, @fps)
		end
		def initialize(frame = 0, fps = 0)
			@frame = frame.to_i
			@fps = fps.to_i
		end
		def is_equal_to_time? time
			equal = FALSE
			if valid? and time and time.respond_to?(:valid) and time.valid? then
				if (@fps == time.fps) then
					equal = (@frame == time.frame)
				else
					# make copies so neither time is changed
					time1 = copy_time
					time2 = time.copy_time
					time1.synchronize time2
					equal = (time1.frame == time2.frame)
				end
			end
			equal
		end
		def less_than? time 
			less = false
			if valid? and time and time.respond_to?(:valid) and time.valid? then
				if @fps == time.fps then
					less = (@frame < time.frame)
				else
					# make copies so neither time is changed
					time1 = copy_time
					time2 = time.copy_time
					time1.synchronize time2
					less = (time1.frame <  time2.frame)
				end
			end
			less	
		end
		def max time
			if time and time.valid? then
				synchronize time
				@frame = [time.frame, @frame].max
			end
		end
		def min time
			if time and time.respond_to?(:valid) and time.valid? then
				synchronize time
				@frame = [time.frame, @frame].min
			end
		end
		def multiply(number, rounding = :round)
			number = number.to_f if number.respond_to? :to_f
			@frame = (@frame.to_f * number).send(rounding)
		end
		def ratio time
			n = 0
			if valid? and time and time.respond_to?(:valid) and time.valid? then
				if (@fps == time.fps) 
					n = @frame.to_f / time.frame.to_f
				else
					# make copies so neither time is changed
					time1 = copy_time
					time2 = time.copy_time
					time1.synchronize time2
					n = time1.frame.to_f / time2.frame.to_f
				end
			end
			n
		end
		def scale(rate, rounding = :round)
			rate = rate.to_i if rate.respond_to? :to_i
			if 0 < rate and rate != @fps then
				if 0 < @fps
					floated = @frame.to_f / (@fps.to_f / rate.to_f)
					floated = floated.send(rounding) if rounding
					@frame = floated
				end
				@fps = rate
			end
		end
		def subtract time
			synchronize time
			subtracted = time.frame
			subtracted -= subtracted - @frame if subtracted > @frame
			@frame -= subtracted
			subtracted
		end
		def synchronize(time, rounding = :round)
			if time and time.respond_to?(:fps) and time.respond_to?(:scale) then
				if time.fps != @fps then
					gcf = __lcm(time.fps, @fps)
					scale(gcf, rounding)
					time.scale(gcf, rounding)
				end
			end
		end
		def valid?
			(0 < @fps and 0 <= @frame)
		end
		def __gcd(a, b) # uint
			t = 0
			while (b != 0) do
				t = b
				b = a % b
				a = t
			end
			a
		end
		def __lcm(a, b)
			(a * b / __gcd(a, b))
		end	
	end
end
