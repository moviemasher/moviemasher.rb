require_relative 'helpers/spec_helper'

describe File.basename(__FILE__) do
  before(:all) do
    @input = spec_input_from_file(spec_generate_rgb_video)
    @output = spec_file('outputs', 'image_16x9_jpg')
  end
  context 'square video to 19:6 image' do
    it 'correctly saves blue image with -0.1 offset' do
      @output[:offset] = -0.1
      @output[:path] = 'ninety_blue'
      file = spec_process_job_files(@input, @output)
      expect_color_image(BLUE, file)
    end
    it 'correctly saves green image with 50% offset' do
      @output[:offset] = '50%'
      @output[:path] = 'fifty_green'
      file = spec_process_job_files(@input, @output)
      expect_color_image(GREEN, file)
    end
    it 'correctly saves red image with no offset' do
      @output[:offset] = ''
      @output[:path] = 'none_red'
      file = spec_process_job_files(@input, @output)
      expect_color_image(RED, file)
    end
  end
end
