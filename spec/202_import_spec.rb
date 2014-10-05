
require_relative 'helpers/spec_helper'

describe File.basename(__FILE__) do
	context "square image into 19:6 image" do
		it "correctly scales down to width" do		
			job, processed_job = spec_process_job_files 'image_square', 'image_16x9_jpg'
			output = job['outputs'][0]
			input = job['inputs'][0]
			destination_file = spec_job_output_path job, processed_job
			rendered_dimensions = cache_get_info(destination_file, 'dimensions')
			expect(rendered_dimensions).to_not be_nil
			rendered_dimensions = rendered_dimensions.split 'x'
			output_dimensions = output['dimensions'].split 'x'
			expect(rendered_dimensions[0].to_i).to eq output_dimensions[0].to_i
			expect(rendered_dimensions[1].to_i).to_not eq output_dimensions[1].to_i
		end
		
	end
	context "square video to 19:6 sequence" do
		it "correctly scales down to width" do
			job, processed_job = spec_process_job_files('video_square_file', 'sequence_16x9_jpg')
			output = job['outputs'][0]
			input = job['inputs'][0]
			destination_file = spec_job_output_path job, processed_job
			rendered_dimensions = cache_get_info(destination_file, 'dimensions')
			expect(rendered_dimensions).to_not be_nil
			rendered_dimensions = rendered_dimensions.split 'x'
			output_dimensions = output['dimensions'].split 'x'
			expect(rendered_dimensions[0].to_i).to eq output_dimensions[0].to_i
			expect(rendered_dimensions[1].to_i).to_not eq output_dimensions[1].to_i
			
		end
	end
	context "audio to audio" do
		it "generates file of correct duration" do
			spec_process_job_files 'audio_file', 'audio_mp3'
		end
	end
	context "audio to waveform png" do
		it "generates file of correct dimensions" do
			job, processed_job = spec_process_job_files 'audio_file', 'waveform_png'
		end
	end
	context "4:3 image into square image" do
		it "correctly scales down to height when input is landscale" do		
			job, processed_job = spec_process_job_files 'image_horz_lg_4x3', 'image_square_jpg'
			output = job['outputs'][0]
			input = job['inputs'][0]
			destination_file = spec_job_output_path job, processed_job
			rendered_dimensions = cache_get_info(destination_file, 'dimensions')
			expect(rendered_dimensions).to_not be_nil
			rendered_dimensions = rendered_dimensions.split 'x'
			output_dimensions = output['dimensions'].split 'x'
			#puts "output_dimensions #{output_dimensions}"
			#puts "rendered_dimensions #{rendered_dimensions}"
			expect(rendered_dimensions[0].to_i).to_not eq output_dimensions[0].to_i
			expect(rendered_dimensions[1].to_i).to eq output_dimensions[1].to_i
		end
		it "correctly scales down to width when input is portrait" do		
			job, processed_job = spec_process_job_files 'image_vert_lg_4x3', 'image_square_jpg'
			output = job['outputs'][0]
			input = job['inputs'][0]
			destination_file = spec_job_output_path job, processed_job
			rendered_dimensions = cache_get_info(destination_file, 'dimensions')
			expect(rendered_dimensions).to_not be_nil
			rendered_dimensions = rendered_dimensions.split 'x'
			output_dimensions = output['dimensions'].split 'x'
			expect(rendered_dimensions[0].to_i).to eq output_dimensions[0].to_i
			expect(rendered_dimensions[1].to_i).to_not eq output_dimensions[1].to_i
		end
	end
	context "4:3 image into 19:6 image" do
		it "correctly scales down to width when input is landscale" do		
			job, processed_job = spec_process_job_files 'image_horz_lg_4x3', 'image_16x9_jpg'
			output = job['outputs'][0]
			input = job['inputs'][0]
			destination_file = spec_job_output_path job, processed_job
			rendered_dimensions = cache_get_info(destination_file, 'dimensions')
			expect(rendered_dimensions).to_not be_nil
			rendered_dimensions = rendered_dimensions.split 'x'
			output_dimensions = output['dimensions'].split 'x'
			expect(rendered_dimensions[0].to_i).to eq output_dimensions[0].to_i
			expect(rendered_dimensions[1].to_i).to_not eq output_dimensions[1].to_i
		end
		it "correctly scales down to width when input is portrait" do		
			job, processed_job = spec_process_job_files 'image_vert_lg_4x3', 'image_16x9_jpg'
			output = job['outputs'][0]
			input = job['inputs'][0]
			destination_file = spec_job_output_path job, processed_job
			rendered_dimensions = cache_get_info(destination_file, 'dimensions')
			expect(rendered_dimensions).to_not be_nil
			rendered_dimensions = rendered_dimensions.split 'x'
			output_dimensions = output['dimensions'].split 'x'
			expect(rendered_dimensions[0].to_i).to eq output_dimensions[0].to_i
			expect(rendered_dimensions[1].to_i).to_not eq output_dimensions[1].to_i
		end
	end
end