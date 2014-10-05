
require_relative 'helpers/spec_helper'

describe File.basename(__FILE__) do
	context "MovieMasher::FilterHelpers" do
		it "rgba(0,0,0,0.5)" do
			expect(MovieMasher::FilterHelpers.send :rgba, '0,0,0,0.5').to eq "0x000000@0.5"
		end
		it "mm_horz returns as expected" do
			scope = Hash.new
			scope[:size] = 0.5
			scope[:mm_width] = 320
			expect(MovieMasher::FilterHelpers.send :mm_horz, 'size', scope).to eq "160"
		end
	end
end