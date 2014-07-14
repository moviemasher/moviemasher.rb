
require_relative 'spec_helper'

describe "Importing..." do
	context "image to image" do
		it "does not raise an error" do
			spec_job_mash_simple 'image_file', 'image_jpg'
		end
	end
	context "video to sequence" do
		it "does not raise an error" do
			spec_job_mash_simple 'video_file', 'sequence_jpg'
		end
	end
	context "audio to audio" do
		it "does not raise an error" do
			spec_job_mash_simple 'audio_file', 'audio_mp3'
		end
	end
end