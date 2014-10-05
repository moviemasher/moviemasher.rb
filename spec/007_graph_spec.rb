
require_relative 'helpers/spec_helper'

describe File.basename(__FILE__) do
	context "Graph#command" do
		it "returns correct filter string for simple background" do
			graph = MovieMasher::Graph.new(Hash.new, MovieMasher::FrameRange.new(3, 2, 1), 'blue')
			output = Hash.new
			output[:fps] = 30
			output[:dimensions] = '320x240'
			backcolor = 'red'
			expect(graph.command output).to eq 'color=color=blue:size=320x240:duration=2.0:rate=30'
		end
		it "returns correct filter string for simple video" do
			graph = MovieMasher::Graph.new(Hash.new, MovieMasher::FrameRange.new(0, 2, 1), 'blue')
			output = Hash.new
			output[:fps] = 30
			output[:dimensions] = '320x240'
			backcolor = 'red'
			input = Hash.new
			input[:type] = MovieMasher::Type::Video
			input[:cached_file] = 'video.mov'
			input[:duration] = 10.0
			input[:dimensions] = '600x400'
			input[:length_seconds] = 2.0
			input[:trim_seconds] = 2.0
			input[:range] = MovieMasher::FrameRange.new(0, input[:length_seconds], 1.0)
			MovieMasher::__init_input input
			MovieMasher::__init_output output
			graph.create_layer input
			expect(graph.command output).to eq 'color=color=blue:size=320x240:duration=2.0:rate=30[layer0];movie=filename=video.mov,trim=duration=2.0:start=2.0,fps=fps=30.0,setpts=expr=PTS-STARTPTS,scale=width=320.0:height=240.0[layer1];[layer0][layer1]overlay=x=0.0:y=0.0'
		end
	end
	context "HashFilter#command" do
		it "returns correct filter string for simple filter" do
			filter = MovieMasher::HashFilter.new 'filter', :param1 => 'value1', :param2 => 'value2'
			expect(filter.command).to eq 'filter=param1=value1:param2=value2'
		end
		it "returns correct filter string for simple evaluated filter" do
			filter = MovieMasher::HashFilter.new 'filter', :param1 => 'value1', :param2 => 'value2'
			expect(filter.command :value1 => 1, :value2 => 2).to eq 'filter=param1=1.0:param2=2.0'
		end
		it "returns correct filter string for evaluated filter" do
			filter = MovieMasher::HashFilter.new 'filter', :param1 => 'value1+value2', :param2 => 'value2*2'
			expect(filter.command :value1 => 1, :value2 => 2).to eq 'filter=param1=3.0:param2=4.0'
		end
	end
	context "VideoLayer#command" do
		it "returns correct filter string for video chain" do
			input = Hash.new
			input[:type] = MovieMasher::Type::Video
			input[:cached_file] = 'video.mov'
			input[:duration] = 10.0
			input[:dimensions] = '600x400'
			input[:length_seconds] = 2.0
			input[:trim_seconds] = 2.0
			
			chain = MovieMasher::VideoLayer.new input
			output = Hash.new
			output[:fps] = 30
			output[:dimensions] = '320x240'
			backcolor = 'red'
			MovieMasher.__init_input input
			MovieMasher.__init_output output
			
			options = Hash.new #MovieMasher.output_options output, backcolor, MovieMasher::FrameRange.new(0, input[:length_seconds], 1)
			options[:mm_duration] = input[:length_seconds]
			options[:mm_dimensions] = output[:dimensions]			
			options[:mm_backcolor] = @backcolor || output[:backcolor] || 'black'
			options[:mm_fps] = output[:fps]			
			options[:mm_width], options[:mm_height] = options[:mm_dimensions].split 'x'
			
			
			
			expect(chain.command options).to eq 'movie=filename=video.mov,trim=duration=2.0:start=2.0,fps=fps=30.0,setpts=expr=PTS-STARTPTS,scale=w=320.0:h=240.0,setsar=sar=1.0:max=1.0'
		end
	end
	
end