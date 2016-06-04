
require_relative 'helpers/spec_helper'

describe File.basename(__FILE__) do
  context 'audio to audio' do
    it 'correctly renders audio file volume' do
      spec_process_job_files 'audio_file_volume', 'audio_mp3'
    end
    it 'generates file of correct duration' do
      spec_process_job_files 'audio_file', 'audio_mp3'
    end
  end
end
