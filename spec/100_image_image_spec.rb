require_relative 'helpers/spec_helper'

describe File.basename(__FILE__) do
  context 'image to image' do
    it 'fill none correctly scales down to width when input is portrait' do
      image_path = MagickGenerator.image_file(width: XL4X3H, height: XL4X3W)
      image_input = {
        fill: 'none', id: "#{XL4X3H}X#{XL4X3W}", source: image_path,
        type: 'image'
      }
      size = 'SM'
      file_name = "image-#{R4X3}-#{size.downcase}-jpg"
      destination_file = spec_process_job_files(image_input, file_name)
      height = (XL4X3W.to_f * (SM4X3W.to_f / XL4X3H)).to_i
      dimensions = "#{SM4X3W}x#{height}"
      expect_dimensions(destination_file, dimensions)
    end
    it 'fill crop correctly removes extra' do
      RATIOS.each do |inner|
        RATIOS.each do |outer|
          SIZES.each do |size|
            image_path = MagickGenerator.ratio_image_file(
              fore: RED, inner: inner, outer: outer,
              width: MagickGenerator.const_get("#{size}#{outer.upcase}W")
            )
            image_input = {
              fill: 'crop', id: "#{inner}-#{outer}", source: image_path,
              type: 'image'
            }
            fname = "image-#{inner}-#{size.downcase}-jpg"
            expect_color_image(RED, spec_process_job_files(image_input, fname))
          end
        end
      end
    end
  end
end
