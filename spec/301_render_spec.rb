
require_relative 'helpers/spec_helper'

describe File.basename(__FILE__) do
	context "spec_process_job_files" do
		it "correctly renders mash transition" do
			spec_process_job_files 'mash_transition'
		end
		it "correctly renders mash pan" do
			spec_process_job_files 'mash_pan'	
		end
		it "correctly renders mash overlays" do
			spec_process_job_files 'mash_overlays'
		end
		it "correctly renders mash fill" do
			spec_process_job_files 'mash_fill'			
		end
		it "correctly renders mash color video" do
			spec_process_job_files 'mash_color_video'
		end
		it "correctly renders audio file volume" do
			spec_process_job_files 'audio_file_volume', 'audio_mp3'
		end
		it "correctly renders mash text" do
			spec_process_job_files 'mash_text'	
			#expect(true).to be_false
		end
		it "correctly renders a video file" do
			spec_process_job_files 'video_16x9'
		end
		it "correctly renders mash color" do
			spec_process_job_files 'mash_color'			
		end
	end
end