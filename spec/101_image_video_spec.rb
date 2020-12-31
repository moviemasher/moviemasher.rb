require_relative 'helpers/spec_helper'

describe File.basename(__FILE__) do
  context 'image to video' do
    it 'generates video from images' do
      spec_generate_rgb_video(red: 1.5, green: 4.6, blue: 2.2)
    end
  end
end
