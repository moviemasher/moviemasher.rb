module MovieMasher
	class TimeRange
		private
		def self.__gcd(a, b) # uint
			t = 0
			while (b != 0) do
				t = b
				b = a % b
				a = t
			end
			a
		end
		def self.__lcm(a, b)
			(a * b / __gcd(a, b))
		end	
		def self.__scale(time, rate, rounding = :round) 
			if 0 < time.length
				__scale_time(time, rate, rounding);
			else
				if 0 < rate and time.rate != rate then
					if 0 < time.rate then
						floated = time.length.to_f / (time.rate.to_f / rate.to_f)
						floated = floated.send(rounding) if (rounding) 
						time.length = [1, floated].max
					end
					__scale_time(time, rate, rounding);
				end
			end
		end
		def self.__scale_time(time, rate, rounding = :round)
			rate = rate.to_i if rate.respond_to? :to_i
			if 0 < rate and rate != time.rate then
				if 0 < time.rate
					floated = time.start.to_f / (time.rate.to_f / rate.to_f)
					floated = floated.send(rounding) if rounding
					time.start = floated
				end
				time.rate = rate
			end
		end
		public
		def dup
			TimeRange.new @start, @length, @rate
		end
		def end_seconds
			TimeRange.new(stop, rate).start_seconds
		end
		def equals? range
			equal = false
			if range and 0 < range.rate and 0 <= range.start then
				if (rate == range.rate) 
					equal = ((start == range.start) and (length == range.length))
				else
					# make copies so neither range is changed
					range1 = dup
					range2 = range.dup
					range1.synchronize range2
					equal = ((range1.start == range2.start) and (range1.length == range2.length))
				end
			end
			equal
		end
		def initialize (start = 0, rate = 0, length = 1)
			@length = length #.to_i
			@start = start.to_i
			@rate = rate.to_i
		end
		def intersection range
			result = nil
			range1 = self
			range2 = range
			if range1.rate != range2.rate then
				range1 = range1.dup
				range2 = range2.dup
				range1.synchronize range2
			end
			last_start = [range1.start, range2.start].max
			first_end = [range1.stop, range2.stop].min
			if (last_start < first_end) then
				result = TimeRange.new(last_start, range1.rate, first_end - last_start)
			end
			result
		end
		def length
			@length
		end
		def length= n
			@length = n
		end
		def length_seconds(precision = 3)
			FloatUtil.precision((@length.to_f / @rate.to_f), precision)
		end
		def rate
			@rate
		end
		def rate= n
			@rate = n
		end
		def start
			@start
		end
		def start= n
			@start = n
		end
		def start_seconds precision = 3
			FloatUtil.precision((@start.to_f / @rate.to_f), precision)
		end
		def stop
			start + length
		end
		def synchronize(time, rounding = :round)
			if time and time.respond_to?(:rate) and time.respond_to?(:scale) then
				if time.rate != @rate then
					gcf = TimeRange.__lcm(time.rate, @rate)
					scale(gcf, rounding)
					TimeRange.__scale(time, gcf, rounding)
				end
			end
		end
	end	
end
