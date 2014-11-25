
require_relative 'helpers/spec_helper'


describe File.basename(__FILE__) do
	context "image to image" do
		it "fill none correctly scales down to width when input is portrait" do
			image_path = MagickGenerator.image_file :width => XL4x3H, :height => XL4x3W
			image_input = {:fill => 'none', :id => "#{XL4x3H}x#{XL4x3W}", :source => image_path, :type => 'image'}
			size = 'SM'
			destination_file = spec_process_job_files(image_input, "image-#{R4x3}-#{size.downcase}-jpg")
			dimensions = "#{SM4x3W}x#{(XL4x3W.to_f * (SM4x3W.to_f / XL4x3H.to_f)).to_i}"
			expect_dimensions(destination_file, dimensions)
		end
		it "fill crop correctly removes extra" do		
			RATIOS.each do |inner|
				RATIOS.each do |outer|
					SIZES.each do |size|
						#puts "    #{size}: #{inner} from #{outer}"
						image_path = MagickGenerator.ratio_image_file :fore => RED, :inner => inner, :outer => outer, :width => MagickGenerator.const_get("#{size}#{outer}W".to_sym)
						image_input = {:fill => 'crop', :id => "#{inner}-#{outer}", :source => image_path, :type => 'image'}
						expect_color_image(RED, spec_process_job_files(image_input, "image-#{inner}-#{size.downcase}-jpg"))
					end
				end
			end
		end
	end
end