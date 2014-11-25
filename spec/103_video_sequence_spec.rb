
require_relative 'helpers/spec_helper'

describe File.basename(__FILE__) do

	context "square video to 19:6 sequence" do
		it "correctly scales down to width" do
			spec_process_job_files('video_square_file', 'sequence_16x9_jpg')
		end
	end
end