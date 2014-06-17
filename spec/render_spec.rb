
require_relative 'spec_helper'

describe "Rendering..." do
	context "MovieMasher.process" do
		it "correctly renders mash ken burns" do
			spec_job_mash_simple 'mash_kenburns_overlay'			
		end
		it "correctly renders mash overlays" do
			spec_job_mash_simple 'mash_overlays'
		end
		it "correctly renders mash fill" do
			spec_job_mash_simple 'mash_fill'			
		end
		it "correctly renders a trimmed video file" do
			spec_job_mash_simple 'video_file'
		end
		it "correctly renders mash color video" do
			spec_job_mash_simple 'mash_color_video'
		end
		it "correctly renders mash color" do
			spec_job_mash_simple 'mash_color'			
		end
		it "correctly renders mash text" do
			spec_job_mash_simple 'mash_text'			
		end
		it "correctly renders mash transition" do
			spec_job_mash_simple 'mash_transition'
		end
	end
end