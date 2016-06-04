
require_relative 'helpers/spec_helper'

describe File.basename(__FILE__) do
  context 'video trim' do
    it 'correctly crops' do
      trimmed_video_path = spec_process_job_files(
        offset: 2, length: 2, id: 'video_trimmed', type: 'video',
        source: spec_generate_rgb_video
      )
      expect_color_video(GREEN, trimmed_video_path)
    end
  end
end
