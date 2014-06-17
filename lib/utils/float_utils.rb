
FLOAT_HUNDRED = 100.to_f unless defined? FLOAT_HUNDRED
FLOAT_NEG_ONE = -1.to_f unless defined? FLOAT_NEG_ONE
FLOAT_ONE = 1.to_f unless defined? FLOAT_ONE
FLOAT_TWO = 2.to_f unless defined? FLOAT_TWO
FLOAT_ZERO = 0.to_f unless defined? FLOAT_ZERO

def float_cmp(f1, f2, precision = 3) # are 2 floats equal
    e = (10 ** precision).to_f
    i1 = (f1.to_f * e).round
    i2 = (f2.to_f * e).round
    (i1 == i2)
end
def float_less(small, big, precision = 3) # is one float smaller than another
	not float_gtre(big, small, precision)
end
def float_gtr(big, small, precision = 3) # is one float bigger than another
    e = (10 ** precision).to_f
    ibig = (big.to_f * e).round
    ismall = (small.to_f * e).round
    (ibig > ismall)
end
def float_gtre(big, small, precision = 3) # is one float bigger or equal to another
    e = (10 ** precision).to_f
    ibig = (big.to_f * e).round
    ismall = (small.to_f * e).round
    (ibig >= ismall)
end
def float_max(a, b, precision = 3)
	(float_gtr(a, b, precision) ? a : b)
end
def float_min(a, b, precision = 3)
	(float_gtr(a, b, precision) ? b : a)
end
def float_sort(a, b)
	(float_gtr(a[0], b[0]) ? 1 : (float_cmp(a[0], b[0]) ? 0 : -1))
end
def float_precision f, precision = 3
	divisor = (precision * 10).to_f
	(f.to_f * divisor).floor / divisor
end