require_relative 'helpers/spec_helper'

describe File.basename(__FILE__) do
  context '__filters_sizing' do
    it 'returns no filters when dimensions match regardless of fill' do
      hash = { dimensions: '320x240', fill: MovieMasher::Fill::SCALE }
      chain = MovieMasher::ChainScaler.new(hash)
      cmd = chain.chain_command(mm_dimensions: '320x240')
      expect(cmd).to be_empty
    end
    it 'returns just scale filter when different sizes but aspect ratio ok' do
      hash = { dimensions: '640x480', fill: MovieMasher::Fill::CROP }
      chain = MovieMasher::ChainScaler.new(hash)
      cmd = chain.chain_command(mm_dimensions: '320x240')
      expect(cmd).to eq 'scale=w=320:h=240'
      hash = { dimensions: '640x480', fill: MovieMasher::Fill::SCALE }
      chain = MovieMasher::ChainScaler.new(hash)
      cmd = chain.chain_command(mm_dimensions: '320x240')
      expect(cmd).to eq 'scale=w=320:h=240'
    end
    it 'returns scale and setsar filter when dimensions differ, stretch fill' do
      hash = { dimensions: '640x240', fill: MovieMasher::Fill::STRETCH }
      chain = MovieMasher::ChainScaler.new(hash)
      cmd = chain.chain_command(mm_dimensions: '320x240')
      expect(cmd).to eq 'scale=w=320:h=240,setsar=sar=1:max=1'
      hash = { dimensions: '320x240', fill: MovieMasher::Fill::STRETCH }
      chain = MovieMasher::ChainScaler.new(hash)
      cmd = chain.chain_command(mm_dimensions: '640x240')
      expect(cmd).to eq 'scale=w=640:h=240,setsar=sar=1:max=1'
    end
    it 'returns just crop filter when only one dimension differs, crop fill' do
      hash = { dimensions: '640x240', fill: MovieMasher::Fill::CROP }
      chain = MovieMasher::ChainScaler.new(hash)
      cmd = chain.chain_command(mm_dimensions: '320x240')
      expect(cmd).to eq 'crop=w=320:h=240:x=160:y=0'
      hash = { dimensions: '320x240', fill: MovieMasher::Fill::CROP }
      chain = MovieMasher::ChainScaler.new(hash)
      cmd = chain.chain_command(mm_dimensions: '640x240')
      expect(cmd).to eq 'crop=w=320:h=120:x=0:y=60'
    end
    it 'returns crop and scale filter when both dimensions differ, crop fill' do
      hash = { dimensions: '640x640', fill: MovieMasher::Fill::CROP }
      chain = MovieMasher::ChainScaler.new(hash)
      cmd = chain.chain_command(mm_dimensions: '320x240')
      expect(cmd).to eq 'crop=w=640:h=480:x=0:y=80,scale=w=320:h=240'
    end
  end
end
