
require_relative 'helpers/spec_helper'

describe File.basename(__FILE__) do
	context "MovieMasher::Float.cmp" do
		it "(1.000001, 1.00001, 3) == true" do
			expect(MovieMasher::Float.cmp(1.000001, 1.00001, 3)).to be_true
		end
		it "(1.001, 1.0001, 4) == false" do
			expect(MovieMasher::Float.cmp(1.001, 1.0001, 4)).to be_false
		end
	end
	context "MovieMasher::Float.gtr" do
		it "(1.000001, 1.00001, 3) == false" do
			expect(MovieMasher::Float.gtr(1.000001, 1.00001, 3)).to be_false
		end
		it "(1.001, 1.0001, 4) == true" do
			expect(MovieMasher::Float.gtr(1.001, 1.0001, 4)).to be_true
		end
	end
	context "MovieMasher::Float.gtre" do
		it "(1.000001, 1.00001, 3) == false" do
			expect(MovieMasher::Float.gtr(1.000001, 1.00001, 3)).to be_false
		end
		it "(1.001, 1.001, 3) == true" do
			expect(MovieMasher::Float.gtr(1.001, 1.0001, 4)).to be_true
		end
	end
end