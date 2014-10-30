module MovieMasher
	module FloatUtil
		Hundred = 100.to_f
		NegOne = -1.to_f 
		One = 1.to_f
		Two = 2.to_f
		Zero = 0.to_f

		def self.cmp(f1, f2, digits = 3) # are 2 floats equal
			e = (10 ** digits).to_f
			i1 = (f1.to_f * e).round.to_i
			i2 = (f2.to_f * e).round.to_i
			(i1 == i2)
		end
		def self.less(small, big, digits = 3) # is one float smaller than another
			not gtre(big, small, digits)
		end
		def self.gtr(big, small, digits = 3) # is one float bigger than another
			e = (10 ** digits).to_f
			ibig = (big.to_f * e).round
			ismall = (small.to_f * e).round
			(ibig > ismall)
		end
		def self.gtre(big, small, digits = 3) # is one float bigger or equal to another
			e = (10 ** digits).to_f
			ibig = (big.to_f * e).round
			ismall = (small.to_f * e).round
			(ibig >= ismall)
		end
		def self.max(a, b, digits = 3)
			(gtr(a, b, digits) ? a : b)
		end
		def self.min(a, b, digits = 3)
			(gtr(a, b, digits) ? b : a)
		end
		def self.sort(a, b)
			(gtr(a[0], b[0]) ? 1 : (cmp(a[0], b[0]) ? 0 : -1))
		end
		def self.string f, digits = 3
			return precision f, digits
			divisor = (10 ** digits.to_i).to_f
			fs = ((f.to_f * divisor).round).to_i.to_s.ljust(digits + 2, '0')
			fs.insert(-1 - digits, '.')
			fs
		end
		def self.precision f, digits = 3
			divisor = (10 ** digits.to_i).to_f
			(f.to_f * divisor).round / divisor
		end
	end
end
