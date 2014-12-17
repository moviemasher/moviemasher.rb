
require 'rspec'
require 'rack'
require 'rack/test'
require_relative 'magick_generator'

include RSpec::Matchers
include MagickGenerator

# delete previous temp directory !!
FileUtils.rm_rf "#{File.dirname(__FILE__)}/../../tmp/spec" if File.directory? "#{File.dirname(__FILE__)}/../../tmp/spec"

require_relative '../../lib/moviemasher.rb'
MovieMasher.configure "#{File.dirname(__FILE__)}/config.yml"

def spec_file dir, id_or_hash
	if id_or_hash
		if id_or_hash.is_a? String
			id = id_or_hash
			path = "#{File.dirname(__FILE__)}/media/json/#{dir}/#{id_or_hash}.json"
			if File.exists? path
				#puts "ID: #{id} HASH: #{id_or_hash}"
				id_or_hash = JSON.parse(File.read path)
				#puts "ID: #{id} FILE: #{id_or_hash}"
			else
				bits = id.split '-'
				id_or_hash = Hash.new
				id_or_hash[:name] = id_or_hash[:type] = bits.shift
				case id_or_hash[:type]
				when 'image'
					id_or_hash[:quality] = '1'
					ratio = bits.shift
					size = bits.shift
					id_or_hash[:dimensions] = MagickGenerator.const_get "#{size.upcase}#{ratio}".to_sym
				end
				id_or_hash[:extension] = bits.shift
			end
		end
	end
	MovieMasher::Job.symbolize_hash! id_or_hash
	id_or_hash
end
def spec_job_from_files(input_id = nil, output_id = nil, destination_id = nil)
	job = Hash.new
	job[:log_level] = 'debug'
	job[:inputs] = Array.new
	job[:callbacks] = Array.new
	job[:outputs] = Array.new
	job[:destination] = spec_file('destinations', destination_id)
	job[:inputs] << spec_file('inputs', input_id) if input_id
	job[:outputs] << spec_file('outputs', output_id) if output_id
	job
end
ModularMedia = Hash.new
def spec_modular_media
	if ModularMedia.empty?
		js_dir = "#{File.dirname(__FILE__)}/../../../angular-moviemasher/app/module"
		js_dirs = Dir["#{js_dir}/*/*.json"]
		js_dirs += Dir["#{js_dir}/*/*/*.json"]
		js_dirs.each do |json_file|
			json_text = File.read json_file
			json_text = "[#{json_text}]" unless json_text.start_with? '['
			medias = JSON.parse(json_text)
			
			medias.each do |media|
				MovieMasher::Job.symbolize_hash! media
				ModularMedia[media[:id]] = media
			end
		end
		#puts ModularMedia
	end
	ModularMedia
end
def spec_callback_file job
	callback = job.callbacks.first
	(callback ? callback[:callback_file] : nil)
end

def spec_output job
	dest_path = job[:destination][:file]
	if not (dest_path and File.exists?(dest_path))
		callback_file =  spec_callback_file job
		dest_path = callback_file if callback_file
	end
	if dest_path and File.directory?(dest_path) then
		dest_path = Dir["#{dest_path}/*"].first
		#puts "DIR: #{dest_path}"
	end
	dest_path
end
def spec_job_data job_data
	unless job_data[:base_source]
		job_data[:base_source] = spec_file('sources', 'base_source_file')
		job_data[:base_source][:directory] = File.dirname(File.dirname(__FILE__))
	end
	input = job_data[:inputs].first
	if input and input[:source] and not input[:source].is_a?(String)
		input[:source][:directory] = File.dirname(__FILE__) 
	end
	if job_data[:destination] and not job_data[:destination][:directory]
		job_data[:destination][:directory] = File.dirname(File.dirname(File.dirname(__FILE__)))
	end
end

def spec_job(input_id = nil, output = 'video_h264', destination = 'file_log')
	job_data = spec_job_from_files input_id, output, destination
	if job_data
		spec_job_data job_data
		unless job_data[:id] 
			input = job_data[:inputs].first
			job_data[:id] = input[:id] if input 
		end
		job_data = MovieMasher::Job.new job_data
	else
		puts "SKIPPED #{input_id} - put angular-moviemasher repo alongside moviemasher.rb repo to test modules"
	end
	job_data
end

def expect_colors_video colors, video_file
	color_frames = MagickGenerator.color_frames video_file
	puts "#{color_frames}\n#{colors}" unless color_frames.length == colors.length
	expect(color_frames.length).to eq colors.length
	color_frames.length.times do |i|
		reported_range = color_frames[i]
		expected_range = colors[i]
		next if reported_range == expected_range
		expected_range = expected_range.dup
		c = expected_range[:color] 
		expected_range[:color] = MagickGenerator.output_color(c, 'jpg')
		next if reported_range == expected_range
		expected_range[:color] = MagickGenerator.output_color(c, 'png')
		expect(reported_range).to eq expected_range
	end
end
def spec_generate_rgb_video options = nil
	options = Hash.new unless options
	options[:red] = 2 unless options[:red]
	options[:green] = 2 unless options[:green]
	options[:blue] = 2 unless options[:blue]
	red_file = MagickGenerator.image_file :back => RED, :width => SM16x9W, :height => SM16x9H
	green_file = MagickGenerator.image_file :back => GREEN, :width => SM16x9W, :height => SM16x9H
	blue_file = MagickGenerator.image_file :back => BLUE, :width => SM16x9W, :height => SM16x9H
	job = spec_job
	job[:inputs] << {:length => options[:red], :id => "red", :source => red_file, :type => 'image'}
	job[:inputs] << {:length => options[:green], :id => "green", :source => green_file, :type => 'image'}
	job[:inputs] << {:length => options[:blue], :id => "blue", :source => blue_file, :type => 'image'}
	job[:id] = Digest::SHA2.new(256).hexdigest(options.inspect) 
	rendered_video_path = spec_process_job job
	fps = job[:outputs].first.video_rate.to_i
	colors = Array.new
	frame = -1
	frames = options[:red] * fps
	colors << { :color => RED, :frames => [0, frames - 1] }
	frame += frames
	frames = options[:green] * fps
	colors << { :color => GREEN, :frames => [frame, frames] }
	frame += frames
	frames = options[:blue] * fps
	colors << { :color => BLUE, :frames => [frame, frames] }
	expect_colors_video(colors, rendered_video_path)
	rendered_video_path
end


def expect_color_video color, video_file
	video_duration = MovieMasher::Job.get_info(video_file, 'duration').to_f
	video_rate = MovieMasher::Job.get_info(video_file, 'fps').to_f
	expect_colors_video [{:color => color, :frames => [0, (video_rate * video_duration).to_i]}], video_file
end
def spec_process_job_files(input_id, output = 'video_h264', destination = 'file_log')
	job = spec_job(input_id, output, destination)
	(job ? spec_process_job(job) : nil)
end
def spec_magick job
	mod_media = nil
	magick_path = "magick/"
	job[:inputs].each do |input|
		if MovieMasher::Input::TypeMash == input[:type]
			mash = input[:mash] 
			if MovieMasher::Mash.hash? mash
				referenced = Hash.new
				MovieMasher::Mash::Tracks.each do |track_type|
					mash[track_type.to_sym].each do |track|
						MovieMasher::Mash.media_count_for_clips(mash, track[:clips], referenced)  
					end
				end
				expect(referenced.empty?).to be_false
				referenced.each do |media_id, reference|
					if reference[:media]
						# generate it
						src = reference[:media][:source]
						if src.start_with? magick_path
							reference[:media][:source] = MagickGenerator.generate src[magick_path.length..-1]							
						end
					else
						mod_media = spec_modular_media unless mod_media
						return nil unless mod_media[media_id]
						mash[:media] << mod_media[media_id]
					end
				end
			end
		else
			# generate it
			src = input[:source]
			if src.is_a?(String) and src.start_with? magick_path
				input[:source] = MagickGenerator.generate src[magick_path.length..-1]							
			end
		end
	end
end

def spec_process_job job, expect_error = nil
	spec_magick job
	job = MovieMasher.process job
	if job[:error] and not expect_error
		puts job[:error] 
		puts job[:commands]
	end
	expect(! job[:error]).to eq ! expect_error
	destination_file = spec_output job
	expect(destination_file).to_not be_nil
	expect(File.exists?(destination_file)).to be_true
	output = job.outputs.first
	if output
		case output[:type]
		when MovieMasher::Output::TypeAudio, MovieMasher::Output::TypeVideo
			expect_duration destination_file, job[:duration]
		end
		input = job.inputs.first
		if input and MovieMasher::Input::TypeMash == input[:type]
			expect_dimensions(destination_file, output[:dimensions]) 
		end
		expect_fps(destination_file, output[:video_rate]) if MovieMasher::Output::TypeVideo == output[:type] 
	end
	destination_file
end
def expect_color_image color, path
	ext =  File.extname(path)
	ext = ext[1..-1]
	expect(MagickGenerator.color_of_file path).to eq MagickGenerator.output_color(color, ext)
end

def expect_duration destination_file, duration
	expect(MovieMasher::Job.get_info(destination_file, 'duration').to_f).to be_within(0.1).of duration
end
def expect_fps destination_file, fps
	expect(MovieMasher::Job.get_info(destination_file, 'fps').to_i).to eq fps.to_i
end
def expect_dimensions destination_file, dimensions
	expect(MovieMasher::Job.get_info(destination_file, 'dimensions')).to eq dimensions
end

RSpec.configure do |config|
	config.expect_with :rspec do |c|
		c.syntax = :expect
	end
	config.include Rack::Test::Methods
	config.after(:suite) do
		
  	end
end