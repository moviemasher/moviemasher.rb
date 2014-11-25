
require_relative 'helpers/spec_helper'


describe File.basename(__FILE__) do
	
	context "video trim" do
		it "correctly crops" do		
			rendered_video_path = spec_generate_rgb_video
			
			video_input = {:offset => 2, :length => 2, :id => "video_trimmed", :source => rendered_video_path, :type => 'video'}
			trimmed_video_path = spec_process_job_files video_input
			expect_color_video(GREEN, trimmed_video_path)
		end
	end
end