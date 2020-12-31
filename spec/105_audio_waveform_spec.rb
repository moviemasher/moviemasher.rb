require_relative 'helpers/spec_helper'

describe File.basename(__FILE__) do
  context 'audio to waveform' do
    it 'generates file of correct dimensions' do
      spec_process_job_files 'audio_file', 'waveform_png'
    end
  end
end
