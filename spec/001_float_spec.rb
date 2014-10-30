
require_relative 'helpers/spec_helper'

describe File.basename(__FILE__) do
	context "MovieMasher::FloatUtil.cmp" do
		it "(1.000001, 1.00001, 3) == true" do
			expect(MovieMasher::FloatUtil.cmp(1.000001, 1.00001, 3)).to be_true
		end
		it "(1.001, 1.0001, 4) == false" do
			expect(MovieMasher::FloatUtil.cmp(1.001, 1.0001, 4)).to be_false
		end
	end
	context "MovieMasher::FloatUtil.gtr" do
		it "(1.000001, 1.00001, 3) == false" do
			expect(MovieMasher::FloatUtil.gtr(1.000001, 1.00001, 3)).to be_false
		end
		it "(1.001, 1.0001, 4) == true" do
			expect(MovieMasher::FloatUtil.gtr(1.001, 1.0001, 4)).to be_true
		end
	end
	context "MovieMasher::FloatUtil.gtre" do
		it "(1.000001, 1.00001, 3) == false" do
			expect(MovieMasher::FloatUtil.gtr(1.000001, 1.00001, 3)).to be_false
		end
		it "(1.001, 1.001, 3) == true" do
			expect(MovieMasher::FloatUtil.gtr(1.001, 1.0001, 4)).to be_true
		end
	end
end