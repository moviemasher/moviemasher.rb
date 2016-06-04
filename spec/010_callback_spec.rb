
require_relative 'helpers/spec_helper'

describe File.basename(__FILE__) do
  before(:all) do
    @job_data = spec_job_from_files nil, nil, 'file_log'
    @job_data[:callbacks] << {
      type: MovieMasher::Type::FILE,
      trigger: MovieMasher::Trigger::ERROR,
      name: 'callback.txt',
      directory: @job_data[:destination][:directory],
      data: { result: '{job.error}' }
    }
    spec_job_data @job_data
    @job_data[:callbacks][0][:directory] = @job_data[:destination][:directory]
    @job_data[:callbacks][0][:path] = @job_data[:destination][:path]
  end
  context 'errors' do
    it 'returns "no inputs specified" when no inputs specified' do
      job = MovieMasher.process @job_data
      callback_file = spec_callback_file job
      data = JSON.parse(File.read(callback_file))
      expect(data['result']).to eq 'no inputs specified'
    end
    it 'returns "no outputs specified" when no outputs specified' do
      @job_data[:inputs] << {}
      job = MovieMasher.process @job_data
      callback_file = spec_callback_file job
      data = JSON.parse(File.read(callback_file))
      expect(data['result']).to eq 'no outputs specified'
    end
  end
  context 'metadata' do
    it 'returns metadata title when okay' do
      @job_data[:inputs] = [spec_file('inputs', 'audio_file')]
      @job_data[:outputs] << spec_file('outputs', 'audio_mp3')
      @job_data[:callbacks][0][:data][:result] = '{job.inputs.0.metadata.title}'
      @job_data[:callbacks][0][:trigger] = 'complete'
      spec_job_data @job_data
      job = MovieMasher.process @job_data
      callback_file = spec_callback_file job
      # puts callback_file
      # puts File.read(callback_file)
      data = JSON.parse(File.read(callback_file))
      expect(data['result']).to eq 'D Celtic 8 Bar 160'
    end
  end
end
