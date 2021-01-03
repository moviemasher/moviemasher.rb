require_relative 'helpers/spec_helper'

describe File.basename(__FILE__) do
  context 'MovieMasher::FilterHelpers' do
    it 'rgba(0,0,0,0.5)' do
      color = MovieMasher::FilterHelpers.send(:rgba, '0,0,0,0.5')
      expect(color).to eq '0x000000@0.5'
    end
    it 'mm_horz returns as expected' do
      scope = {}
      scope[:size] = 0.5
      scope[:mm_width] = 320
      horz = MovieMasher::FilterHelpers.send(:mm_horz, 'size', nil, scope)
      expect(horz).to eq '160'
    end
  end
end
