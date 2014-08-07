
require_relative 'spec_helper'

describe "Rendering..." do
	context "MovieMasher.process" do
		end
		it "correctly renders a video file" do
			spec_job_mash_simple 'video_16x9'
		end
		it "correctly renders mash transition" do
			spec_job_mash_simple 'mash_transition'
		end
		it "correctly renders mash overlays" do
			spec_job_mash_simple 'mash_overlays'
		end
		it "correctly renders mash fill" do
			spec_job_mash_simple 'mash_fill'			
		end
		it "correctly renders mash color video" do
			spec_job_mash_simple 'mash_color_video'
		end
		it "correctly renders mash color" do
			spec_job_mash_simple 'mash_color'			
		end
		it "correctly renders audio file volume" do
			spec_job_mash_simple 'audio_file_volume', 'audio_mp3'
		end
		it "correctly renders mash text" do
			spec_job_mash_simple 'mash_text'			
		end
		it "correctly renders mash pan" do
			spec_job_mash_simple 'mash_pan'	
	end
end