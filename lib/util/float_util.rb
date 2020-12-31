# frozen_string_literal: true

module MovieMasher
  # comparison of floats
  module FloatUtil
    HUNDRED = 100.to_f
    NEG_ONE = -1.to_f
    ONE = 1.to_f
    TWO = 2.to_f
    ZERO = 0.to_f

    class << self
      # are 2 floats equal
      def cmp(float1, float2, digits = 3)
        if digits.zero?
          i1 = float1.to_f.round.to_i
          i2 = float2.to_f.round.to_i
        else
          e = (10**digits).to_f
          i1 = (float1.to_f * e).round.to_i
          i2 = (float2.to_f * e).round.to_i
        end
        (i1 == i2)
      end

      # is one float bigger than another
      def gtr(big, small, digits = 3)
        e = (10**digits).to_f
        ibig = (big.to_f * e).round
        ismall = (small.to_f * e).round
        (ibig > ismall)
      end

      # is big greater or equal to small
      def gtre(big, small, digits = 3)
        e = (10**digits).to_f
        ibig = (big.to_f * e).round
        ismall = (small.to_f * e).round
        (ibig >= ismall)
      end

      # is one float smaller than another
      def less(small, big, digits = 3)
        !gtre(big, small, digits)
      end

      def max(float1, float2, digits = 3)
        (gtr(float1, float2, digits) ? float1 : float2)
      end

      def min(float1, float2, digits = 3)
        (gtr(float1, float2, digits) ? float2 : float1)
      end

      def nonzero(float1)
        float1 && gtr(float1, ZERO)
      end

      def precision(float, digits = 3)
        divisor = (10**digits.to_i).to_f
        (float.to_f * divisor).round / divisor
      end

      def sort(float1, float2)
        if gtr(float1[0], float2[0])
          1
        else
          (cmp(float1[0], float2[0]) ? 0 : -1)
        end
      end

      def string(float, digits = 3)
        precision(float, digits)
      end
    end
  end
end
