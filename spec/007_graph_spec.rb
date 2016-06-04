
require_relative 'helpers/spec_helper'

describe File.basename(__FILE__) do
  context 'Graph#graph_command' do
    it 'returns correct filter string for simple background' do
      mash = { mash: { backcolor: 'blue' } }
      time_range = MovieMasher::TimeRange.new(3, 1, 2)
      graph = MovieMasher::GraphMash.new({}, mash, time_range)
      output = {}
      output[:video_rate] = 30
      output[:dimensions] = '320x240'
      expected_output = 'color=color=blue:duration=2.0:size=320x240:rate=30'
      expect(graph.graph_command(output)).to eq expected_output
    end
    it 'returns correct filter string for simple video' do
      mash = { mash: { backcolor: 'blue' } }
      time_range = MovieMasher::TimeRange.new(3, 1, 2)
      graph = MovieMasher::GraphMash.new({}, mash, time_range)
      output = {}
      output[:video_rate] = 30
      output[:dimensions] = '320x240'
      input = {}
      input[:type] = MovieMasher::Type::VIDEO
      input[:cached_file] = 'video.mov'
      input[:duration] = 10.0
      input[:dimensions] = '600x400'
      input[:length] = 2.0
      input[:offset] = 2.0
      input[:range] = MovieMasher::TimeRange.new(0, 1, input[:length])
      input = MovieMasher::Input.new input
      output = MovieMasher::Output.new output
      graph.add_new_layer input

      expected_output = 'color=color=blue:duration=2.0:size=320x240'\
        ':rate=30[layer0];movie=filename=video.mov,trim=duration=2.0'\
        ':start=2.0,fps=fps=30,setpts=expr=PTS-STARTPTS,scale=width=320'\
        ':height=240,setsar=sar=1:max=1,trim=duration=2.0:start=3.0,'\
        'setpts=expr=PTS-STARTPTS[layer1];[layer0][layer1]overlay=x=0:y=0'
      expect(graph.graph_command(output)).to eq expected_output
    end
  end
  context 'FilterEvaluated#filter_command' do
    it 'returns correct filter string for simple filter' do
      parameters = [
        { name: 'param1', value: 'value1' }, { name: 'param2', value: 'value2' }
      ]
      filter_hash = { id: 'filter', parameters: parameters }
      filter = MovieMasher::FilterEvaluated.new(filter_hash)
      expect(filter.filter_command).to eq 'filter=param1=value1:param2=value2'
    end
    it 'returns correct filter string for simple evaluated filter' do
      parameters = [
        { name: 'param1', value: 'value1' }, { name: 'param2', value: 'value2' }
      ]
      filter_hash = { id: 'filter', parameters: parameters }
      filter = MovieMasher::FilterEvaluated.new(filter_hash)
      expected = 'filter=param1=1:param2=2'
      expect(filter.filter_command(value1: 1, value2: 2)).to eq expected
    end
    it 'returns correct filter string for evaluated filter' do
      parameters = [
        { name: 'param1', value: 'value1+value2' },
        { name: 'param2', value: 'value2*2' }
      ]
      filter_hash = { id: 'filter', parameters: parameters }
      filter = MovieMasher::FilterEvaluated.new(filter_hash)
      expected = 'filter=param1=3:param2=4'
      expect(filter.filter_command(value1: 1, value2: 2)).to eq expected
    end
  end
  context 'LayerRawVideo#layer_command' do
    it 'returns correct filter string for video layer' do
      input = {}
      input[:type] = MovieMasher::Type::VIDEO
      input[:id] = 'video-600x400'
      input[:cached_file] = 'video.mov'
      input[:duration] = 10.0
      input[:dimensions] = '600x400'
      input[:length] = 2.0
      input[:offset] = 2.0

      layer = MovieMasher::LayerRawVideo.new input, input
      output = {}
      output[:video_rate] = 30
      output[:dimensions] = '320x240'
      input = MovieMasher::Input.create input
      output = MovieMasher::Output.create output

      options = {}
      options[:mm_duration] = input[:length]
      options[:mm_dimensions] = output[:dimensions]
      options[:mm_fps] = output[:video_rate]
      mm_dimensions = options[:mm_dimensions]
      options[:mm_width], options[:mm_height] = mm_dimensions.split('x')

      options[:mm_output] = { type: MovieMasher::Type::VIDEO }
      expected = 'movie=filename=video.mov,trim=duration=2.0:start=2.0,fps='\
        'fps=30,setpts=expr=PTS-STARTPTS,scale=w=320:h=240,setsar=sar=1:max=1'
      expect(layer.layer_command(options)).to eq expected
    end
  end
end
