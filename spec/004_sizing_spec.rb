
require_relative 'helpers/spec_helper'

describe File.basename(__FILE__) do
	context "__filters_sizing" do
		it "returns no filters when dimensions match regardless of fill" do
			chain = MovieMasher::FillChain.new "320x240", MovieMasher::Mash::FillScale
			cmd = chain.command({:mm_dimensions => "320x240"})
			expect(cmd).to be_empty
		end
		it "returns just scale filter when different sizes but aspect ratio matches regardless of fill" do
			chain = MovieMasher::FillChain.new "640x480", MovieMasher::Mash::FillCrop
			cmd = chain.command({:mm_dimensions => "320x240"})
			expect(cmd).to eq 'scale=w=320:h=240'

			chain = MovieMasher::FillChain.new "640x480", MovieMasher::Mash::FillScale
			cmd = chain.command({:mm_dimensions => "320x240"})
			expect(cmd).to eq 'scale=w=320:h=240'
		end
		it "returns scale and setsar filter when dimensions differ and fill is stretch" do
			chain = MovieMasher::FillChain.new "640x240", MovieMasher::Mash::FillStretch
			cmd = chain.command({:mm_dimensions => "320x240"})
			expect(cmd).to eq 'scale=w=320:h=240,setsar=sar=1:max=1'

			chain = MovieMasher::FillChain.new "320x240", MovieMasher::Mash::FillStretch
			cmd = chain.command({:mm_dimensions => "640x240"})
			expect(cmd).to eq 'scale=w=640:h=240,setsar=sar=1:max=1'
		end
		it "returns just crop filter when only one dimension differs and fill is crop" do
			chain = MovieMasher::FillChain.new "640x240", MovieMasher::Mash::FillCrop
			cmd = chain.command({:mm_dimensions => "320x240"})
			expect(cmd).to eq 'crop=w=320:h=240:x=160:y=0'

			chain = MovieMasher::FillChain.new "320x240", MovieMasher::Mash::FillCrop
			cmd = chain.command({:mm_dimensions => "640x240"})
			expect(cmd).to eq 'crop=w=320:h=120:x=0:y=60'
	
		end
		it "returns crop and scale filter when both dimensions differ and fill is crop" do
			chain = MovieMasher::FillChain.new "640x640", MovieMasher::Mash::FillCrop
			cmd = chain.command({:mm_dimensions => "320x240"})
			expect(cmd).to eq 'crop=w=640:h=480:x=0:y=80,scale=w=320:h=240'

		end
	end
end