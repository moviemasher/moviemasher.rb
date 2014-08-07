
require_relative 'spec_helper'

describe "float utilities" do
	context "float_cmp" do
		it "(1.000001, 1.00001, 3) == true" do
			expect(float_cmp(1.000001, 1.00001, 3)).to be_true
		end
		it "(1.001, 1.0001, 4) == false" do
			expect(float_cmp(1.001, 1.0001, 4)).to be_false
		end
	end
	context "float_gtr" do
		it "(1.000001, 1.00001, 3) == false" do
			expect(float_gtr(1.000001, 1.00001, 3)).to be_false
		end
		it "(1.001, 1.0001, 4) == true" do
			expect(float_gtr(1.001, 1.0001, 4)).to be_true
		end
	end
	context "float_gtre" do
		it "(1.000001, 1.00001, 3) == false" do
			expect(float_gtr(1.000001, 1.00001, 3)).to be_false
		end
		it "(1.001, 1.001, 3) == true" do
			expect(float_gtr(1.001, 1.0001, 4)).to be_true
		end
	end
end