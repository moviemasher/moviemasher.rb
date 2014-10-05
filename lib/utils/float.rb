module MovieMasher
	module Float
		Hundred = 100.to_f
		NegOne = -1.to_f 
		One = 1.to_f
		Two = 2.to_f
		Zero = 0.to_f

		def self.cmp(f1, f2, precision = 3) # are 2 floats equal
			e = (10 ** precision).to_f
			i1 = (f1.to_f * e).round.to_i
			i2 = (f2.to_f * e).round.to_i
			(i1 == i2)
		end
		def self.less(small, big, precision = 3) # is one float smaller than another
			not gtre(big, small, precision)
		end
		def self.gtr(big, small, precision = 3) # is one float bigger than another
			e = (10 ** precision).to_f
			ibig = (big.to_f * e).round
			ismall = (small.to_f * e).round
			(ibig > ismall)
		end
		def self.gtre(big, small, precision = 3) # is one float bigger or equal to another
			e = (10 ** precision).to_f
			ibig = (big.to_f * e).round
			ismall = (small.to_f * e).round
			(ibig >= ismall)
		end
		def self.max(a, b, precision = 3)
			(gtr(a, b, precision) ? a : b)
		end
		def self.min(a, b, precision = 3)
			(gtr(a, b, precision) ? b : a)
		end
		def self.sort(a, b)
			(gtr(a[0], b[0]) ? 1 : (cmp(a[0], b[0]) ? 0 : -1))
		end
		def self.string f, precision = 3
			divisor = (10 ** precision.to_i).to_f
			fs = ((f.to_f * divisor).round).to_i.to_s.ljust(precision + 2, '0')
			fs.insert(-1 - precision, '.')
			fs
		end
		def self.precision f, precision = 3
			divisor = (10 ** precision.to_i).to_f
			(f.to_f * divisor).round / divisor
		end
	end
end
