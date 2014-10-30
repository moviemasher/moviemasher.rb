
require_relative 'helpers/spec_helper'

describe File.basename(__FILE__) do
	context "Graph#graph_command" do
		it "returns correct filter string for simple background" do
			graph = MovieMasher::GraphMash.new({:source => {:backcolor => 'blue'}}, MovieMasher::TimeRange.new(3, 1, 2))
			output = Hash.new
			output[:video_rate] = 30
			output[:dimensions] = '320x240'
			expect(graph.graph_command output).to eq 'color=color=blue:duration=2.0:size=320x240:rate=30'
		end
		it "returns correct filter string for simple video" do
			graph = MovieMasher::GraphMash.new({:source => {:backcolor => 'blue'}}, MovieMasher::TimeRange.new(3, 1, 2))
			output = Hash.new
			output[:video_rate] = 30
			output[:dimensions] = '320x240'
			input = Hash.new
			input[:type] = MovieMasher::Input::TypeVideo
			input[:cached_file] = 'video.mov'
			input[:duration] = 10.0
			input[:dimensions] = '600x400'
			input[:length] = 2.0
			input[:offset] = 2.0
			input[:range] = MovieMasher::TimeRange.new(0, 1, input[:length])
			input = MovieMasher::Job.send :__init_input, input
			output = MovieMasher::Job.send :__init_output,  output
			graph.add_new_layer input
			expect(graph.graph_command output).to eq 'color=color=blue:duration=2.0:size=320x240:rate=30[layer0];movie=filename=video.mov,trim=duration=2.0:start=2.0,fps=fps=30,setpts=expr=PTS-STARTPTS,scale=width=320.0:height=240.0,setsar=sar=1.0:max=1.0,trim=duration=2.0:start=3.0,setpts=expr=PTS-STARTPTS[layer1];[layer0][layer1]overlay=x=0.0:y=0.0'
		end
	end
	context "FilterEvaluated#filter_command" do
		it "returns correct filter string for simple filter" do
			filter = MovieMasher::FilterEvaluated.new({:id => 'filter', :parameters => [{:name => 'param1', :value => 'value1'}, {:name => 'param2', :value => 'value2'}]})
			expect(filter.filter_command).to eq 'filter=param1=value1:param2=value2'
		end
		it "returns correct filter string for simple evaluated filter" do
			filter = MovieMasher::FilterEvaluated.new({:id => 'filter', :parameters => [{:name => 'param1', :value => 'value1'}, {:name => 'param2', :value => 'value2'}]})
			expect(filter.filter_command({:value1 => 1, :value2 => 2})).to eq 'filter=param1=1.0:param2=2.0'
		end
		it "returns correct filter string for evaluated filter" do
			filter = MovieMasher::FilterEvaluated.new({:id => 'filter', :parameters => [{:name => 'param1', :value => 'value1+value2'}, {:name => 'param2', :value => 'value2*2'}]})
			expect(filter.filter_command({:value1 => 1, :value2 => 2})).to eq 'filter=param1=3.0:param2=4.0'
		end
	end
	context "LayerRawVideo#layer_command" do
		it "returns correct filter string for video layer" do
			input = Hash.new
			input[:type] = MovieMasher::Input::TypeVideo
			input[:id] = 'video-600x400'
			input[:cached_file] = 'video.mov'
			input[:duration] = 10.0
			input[:dimensions] = '600x400'
			input[:length] = 2.0
			input[:offset] = 2.0
			
			layer = MovieMasher::LayerRawVideo.new input, input
			output = Hash.new
			output[:video_rate] = 30
			output[:dimensions] = '320x240'
			input = MovieMasher::Job.send :__init_input,  input
			output = MovieMasher::Job.send :__init_output,  output
			
			options = Hash.new 
			options[:mm_duration] = input[:length]
			options[:mm_dimensions] = output[:dimensions]			
			options[:mm_fps] = output[:video_rate]			
			options[:mm_width], options[:mm_height] = options[:mm_dimensions].split 'x'
			
			expect(layer.layer_command options, {:type => MovieMasher::Input::TypeVideo}).to eq 'movie=filename=video.mov,trim=duration=2.0:start=2.0,fps=fps=30,setpts=expr=PTS-STARTPTS,scale=w=320:h=240,setsar=sar=1:max=1'
		end
	end
	
end