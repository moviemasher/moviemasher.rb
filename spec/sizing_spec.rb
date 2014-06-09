
require_relative 'spec_helper'

describe "Sizing..." do
	context "__filters_sizing" do
		it "returns no filters when dimensions match regardless of fill" do
			sizing_filters = MovieMasher.__filters_sizing "320x240", "320x240", 'green', MovieMasher::MASH_FILL_SCALE
			expect(sizing_filters).to be_an Array
			expect(sizing_filters.length).to eq 0 
		end
		it "returns just scale filter when different sizes but aspect ratio matches regardless of fill" do
			sizing_filters = MovieMasher.__filters_sizing "640x480", "320x240", 'green', MovieMasher::MASH_FILL_CROP
			expect(sizing_filters).to be_an Array
			expect(sizing_filters.length).to eq 1
			expect(sizing_filters[0][:id]).to eq 'scale'
			expect(sizing_filters[0][:parameters][:w].to_s).to eq '320'
			expect(sizing_filters[0][:parameters][:h].to_s).to eq '240'
			sizing_filters = MovieMasher.__filters_sizing "320x240","640x480", 'green', MovieMasher::MASH_FILL_SCALE
			expect(sizing_filters).to be_an Array
			expect(sizing_filters.length).to eq 1
			expect(sizing_filters[0][:id]).to eq 'scale'
			expect(sizing_filters[0][:parameters][:w].to_s).to eq '640'
			expect(sizing_filters[0][:parameters][:h].to_s).to eq '480'
		end
		it "returns scale and setsar filter when dimensions differ and fill is stretch" do
			sizing_filters = MovieMasher.__filters_sizing "640x240", "320x240", 'green', MovieMasher::MASH_FILL_STRETCH
			expect(sizing_filters).to be_an Array
			expect(sizing_filters.length).to eq 2
			expect(sizing_filters[0][:id]).to eq 'scale'
			expect(sizing_filters[0][:parameters][:w].to_s).to eq '320'
			expect(sizing_filters[0][:parameters][:h].to_s).to eq '240'
			expect(sizing_filters[1][:id]).to eq 'setsar'
			expect(sizing_filters[1][:parameters][:sar].to_s).to eq '1'
			expect(sizing_filters[1][:parameters][:max].to_s).to eq '1'
			sizing_filters = MovieMasher.__filters_sizing "320x240", "640x240", 'green', MovieMasher::MASH_FILL_STRETCH
			expect(sizing_filters).to be_an Array
			expect(sizing_filters.length).to eq 2
			expect(sizing_filters[0][:id]).to eq 'scale'
			expect(sizing_filters[0][:parameters][:w].to_s).to eq '640'
			expect(sizing_filters[0][:parameters][:h].to_s).to eq '240'
			expect(sizing_filters[1][:id]).to eq 'setsar'
			expect(sizing_filters[1][:parameters][:sar].to_s).to eq '1'
			expect(sizing_filters[1][:parameters][:max].to_s).to eq '1'
		end
		it "returns just crop filter when only one dimension differs and fill is crop" do
			sizing_filters = MovieMasher.__filters_sizing "640x240", "320x240", 'green', MovieMasher::MASH_FILL_CROP
			expect(sizing_filters).to be_an Array
			expect(sizing_filters.length).to eq 1
			expect(sizing_filters[0][:id]).to eq 'crop'
			expect(sizing_filters[0][:parameters][:w].to_s).to eq '320'
			expect(sizing_filters[0][:parameters][:h].to_s).to eq '240'
			expect(sizing_filters[0][:parameters][:x].to_s).to eq '160'
			expect(sizing_filters[0][:parameters][:y].to_s).to eq '0'		
			sizing_filters = MovieMasher.__filters_sizing "320x240", "640x240", 'green', MovieMasher::MASH_FILL_CROP
			expect(sizing_filters).to be_an Array
			expect(sizing_filters.length).to eq 1
			expect(sizing_filters[0][:id]).to eq 'crop'
			expect(sizing_filters[0][:parameters][:w].to_s).to eq '320'
			expect(sizing_filters[0][:parameters][:h].to_s).to eq '120'
			expect(sizing_filters[0][:parameters][:x].to_s).to eq '0'
			expect(sizing_filters[0][:parameters][:y].to_s).to eq '60'		
		end
		it "returns crop and scale filter when both dimensions differ and fill is crop" do
			sizing_filters = MovieMasher.__filters_sizing "640x640", "320x240", 'green', MovieMasher::MASH_FILL_CROP
			expect(sizing_filters).to be_an Array
			expect(sizing_filters.length).to eq 2
			expect(sizing_filters[0][:id]).to eq 'crop'
			expect(sizing_filters[0][:parameters][:w].to_s).to eq '640'
			expect(sizing_filters[0][:parameters][:h].to_s).to eq '480'
			expect(sizing_filters[0][:parameters][:x].to_s).to eq '0'
			expect(sizing_filters[0][:parameters][:y].to_s).to eq '80'
			expect(sizing_filters[1][:id]).to eq 'scale'
			expect(sizing_filters[1][:parameters][:w].to_s).to eq '320'
			expect(sizing_filters[1][:parameters][:h].to_s).to eq '240'
		end
	end
end