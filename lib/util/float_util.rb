module MovieMasher
  # comparison of floats
  module FloatUtil
    HUNDRED = 100.to_f
    NEG_ONE = -1.to_f
    ONE = 1.to_f
    TWO = 2.to_f
    ZERO = 0.to_f
    def self.cmp(f1, f2, digits = 3) # are 2 floats equal
      if digits.zero?
        i1 = f1.to_f.round.to_i
        i2 = f2.to_f.round.to_i
      else
        e = (10**digits).to_f
        i1 = (f1.to_f * e).round.to_i
        i2 = (f2.to_f * e).round.to_i
      end
      (i1 == i2)
    end
    def self.less(small, big, digits = 3) # is one float smaller than another
      !gtre(big, small, digits)
    end
    def self.gtr(big, small, digits = 3) # is one float bigger than another
      e = (10**digits).to_f
      ibig = (big.to_f * e).round
      ismall = (small.to_f * e).round
      (ibig > ismall)
    end
    def self.gtre(big, small, digits = 3) # is big greater or equal to small
      e = (10**digits).to_f
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
    def self.nonzero(a)
      a && gtr(a, ZERO)
    end
    def self.sort(a, b)
      if gtr(a[0], b[0])
        1
      else
        (cmp(a[0], b[0]) ? 0 : -1)
      end
    end
    def self.string(f, digits = 3)
      precision f, digits
    end
    def self.precision(f, digits = 3)
      divisor = (10**digits.to_i).to_f
      (f.to_f * divisor).round / divisor
    end
  end
end
