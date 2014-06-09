
require_relative 'spec_helper'

describe "Filter Helpers..." do
	context "MovieMasher::FilterHelpers" do
		it "mm_horz returns as expected" do
			scope = Hash.new
			scope[:size] = 0.5
			scope[:mm_width] = 320
			expect(MovieMasher::FilterHelpers.send :mm_horz, 'size', scope).to eq "160"
		end
	end
end