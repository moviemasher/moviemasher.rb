
require_relative 'spec_helper'

describe "Importing..." do

	context "image to image" do
		it "does not raise an error" do
			job = spec_job_simple 'image_file', 'image_jpg', 'file_log'
			#puts job.inspect
			job['inputs'][0]['source']['directory'] = __dir__
			MovieMasher.process job
		end
	end
	context "video to sequence" do
		it "does not raise an error" do
			job = spec_job_simple 'video_file', 'video_h264', 'file_log'
			#puts job.inspect
			job['inputs'][0]['source']['directory'] = __dir__
			MovieMasher.process job
		end
	end
end