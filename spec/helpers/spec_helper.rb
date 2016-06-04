
require 'rspec'
require 'rack'
require 'rack/test'
require_relative 'magick_generator'

extend RSpec::Matchers
include MagickGenerator

# delete previous temp directory !!
if File.directory?("#{File.dirname(__FILE__)}/../../tmp/spec")
  FileUtils.rm_rf("#{File.dirname(__FILE__)}/../../tmp/spec")
end

require_relative '../../lib/moviemasher.rb'
MovieMasher::FileHelper.safe_path("#{File.dirname(__FILE__)}/../../tmp/spec")
MovieMasher.configure("#{__dir__}/../../config/docker/rspec/config.yml")
def expect_color_image(color, path)
  ext = File.extname(path)
  ext = ext[1..-1]
  expected_color = MagickGenerator.output_color(color, ext)
  expect(MagickGenerator.color_of_file(path)).to eq expected_color
end
def expect_dimensions(destination_file, dimensions)
  expect(MovieMasher::Info.get(destination_file, 'dimensions')).to eq dimensions
end
def expect_duration(destination_file, expected_duration)
  duration = MovieMasher::Info.get(destination_file, 'duration').to_f
  expect(duration).to be_within(0.1).of expected_duration
end
def expect_color_video(color, video_file)
  video_duration = MovieMasher::Info.get(video_file, 'duration').to_f
  video_rate = MovieMasher::Info.get(video_file, 'fps').to_f
  frames = (video_rate * video_duration).to_i
  expect_colors_video([{ color: color, frames: [0, frames] }], video_file)
end
def expect_colors_video(colors, video_file)
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
def expect_fps(destination_file, fps)
  expect(MovieMasher::Info.get(destination_file, 'fps').to_i).to eq fps.to_i
end
def spec_file(dir, id_or_hash)
  if id_or_hash.is_a?(String)
    id = id_or_hash
    path = "#{File.dirname(__FILE__)}/media/json/#{dir}/#{id_or_hash}.json"
    if File.exist?(path)
      id_or_hash = JSON.parse(File.read(path))
    else
      bits = id.split('-')
      id_or_hash = {}
      id_or_hash[:name] = id_or_hash[:type] = bits.shift
      if 'image' == id_or_hash[:type]
        id_or_hash[:quality] = '1'
        ratio = bits.shift
        size = bits.shift
        const_name = "#{size.upcase}#{ratio.upcase}"
        id_or_hash[:dimensions] = MagickGenerator.const_get(const_name)
      end
      id_or_hash[:extension] = bits.shift
    end
  end
  MovieMasher::Hashable.symbolize(id_or_hash)
end
def spec_job_from_files(input_id = nil, output_id = nil, destination_id = nil)
  job = {}
  job[:log_level] = 'debug'
  job[:inputs] = []
  job[:callbacks] = []
  job[:outputs] = []
  job[:destination] = spec_file('destinations', destination_id)
  job[:inputs] << spec_file('inputs', input_id) if input_id
  job[:outputs] << spec_file('outputs', output_id) if output_id
  job
end
def spec_modular_media
  modular_media = Set.new
  js_dir = "#{File.dirname(__FILE__)}/../../../angular-moviemasher/app/module"
  js_dir = File.expand_path(js_dir)
  js_dirs = Dir["#{js_dir}/*/*.json"]
  js_dirs += Dir["#{js_dir}/*/*/*.json"]
  js_dirs.each do |json_file|
    json_text = File.read json_file
    json_text = "[#{json_text}]" unless json_text.start_with? '['
    medias = JSON.parse(json_text)
    medias.each { |m| modular_media << MovieMasher::Hashable.symbolize(m) }
  end
  modular_media.to_a
end
def spec_callback_file(job)
  callback = job.callbacks.first
  (callback ? callback[:callback_file] : nil)
end
def spec_output(job)
  dest_path = job[:destination][:file]
  unless dest_path && File.exist?(dest_path)
    callback_file = spec_callback_file job
    dest_path = callback_file if callback_file
  end
  if dest_path && File.directory?(dest_path)
    dest_path = Dir["#{dest_path}/*"].first
    # puts "DIR: #{dest_path}"
  end
  dest_path
end
def spec_job_data(job_data)
  unless job_data[:base_source]
    job_data[:base_source] = spec_file('sources', 'base_source_file')
    job_data[:base_source][:directory] = "#{__dir__}/../"
  end
  unless job_data[:module_source]
    job_data[:module_source] = spec_file('sources', 'module_source_file')
    job_data[:module_source][:directory] = "#{__dir__}/../../../"
  end
  input = job_data[:inputs].first
  if input && input[:source] && !input[:source].is_a?(String)
    input[:source][:directory] = __dir__
  end
  if job_data[:destination] && !job_data[:destination][:directory]
    job_data[:destination][:directory] = "#{__dir__}/../../"
  end
end
def spec_job(input_id = nil, output = 'video_h264', destination = 'file_log')
  job_data = spec_job_from_files(input_id, output, destination)
  if job_data
    spec_job_data job_data
    unless job_data[:id]
      input = job_data[:inputs].first
      job_data[:id] = input[:id] if input
    end
    job_data = MovieMasher::Job.create(job_data)
  else
    puts "SKIPPED #{input_id} - put angular-moviemasher repo alongside "\
      'moviemasher.rb repo to test modules'
  end
  job_data
end
def spec_generate_rgb_video(options = nil)
  options ||= {}
  options[:red] ||= 2
  options[:green] ||= 2
  options[:blue] ||= 2
  job = spec_job
  %w(red green blue).each do |c|
    source = MagickGenerator.image_file(
      back: MagickGenerator.const_get(c.upcase), width: SM16X9W, height: SM16X9H
    )
    job[:inputs] << {
      length: options[c.to_sym], id: c, type: 'image', source: source
    }
  end
  job[:id] = Digest::SHA2.new(256).hexdigest(options.inspect)
  rendered_video_path = spec_process_job job
  fps = job[:outputs].first.video_rate.to_i
  colors = []
  frame = 0
  frames = options[:red] * fps
  colors << { color: RED, frames: [0, frames] }
  frame += frames
  frames = options[:green] * fps
  colors << { color: GREEN, frames: [frame, frames] }
  frame += frames
  frames = options[:blue] * fps
  colors << { color: BLUE, frames: [frame, frames] }
  expect_colors_video(colors, rendered_video_path)
  rendered_video_path
end
def spec_input_from_file(file, type = 'video', fill = 'none')
  {
    id: File.basename(file, File.extname(file)),
    type: type,
    fill: fill,
    source: file
  }
end
def spec_magick(job)
  job[:inputs].each do |input|
    if MovieMasher::Type::MASH == input[:type]
      mash = input[:mash]
      if MovieMasher::Mash.hash?(mash)
        mash[:media] += spec_modular_media
        refs = {}
        MovieMasher::Type::TRACKS.each do |track_type|
          mash[track_type.to_sym].each do |track|
            MovieMasher::Mash.media_count_for_clips(mash, track[:clips], refs)
          end
        end
        mash[:media] = []
        expect(refs).to_not be_empty
        refs.each do |media_id, reference|
          # puts "reference: #{media_id} #{reference}"
          if reference[:media]
            mash[:media] << reference[:media]
            # generate it
            reference[:media][:source] = spec_source(reference[:media][:source])
          else
            puts "MEDIA NOT FOUND: #{media_id}"
            return nil
          end
        end
      end
    else
      input[:source] = spec_source(input[:source])
    end
  end
end
def spec_process_job(job, expect_error = nil)
  spec_magick(job)
  job = MovieMasher.process(job)
  if job[:error] && !expect_error
    puts job[:error]
    puts job[:commands]
  end
  puts job[:error] if job[:error] && !job[:error] != !expect_error
  expect(!job[:error]).to eq !expect_error
  destination_file = spec_output job
  expect(destination_file).to_not be_nil
  expect(File.exist?(destination_file)).to be_truthy
  output = job.outputs.first
  if output
    case output[:type]
    when MovieMasher::Type::AUDIO, MovieMasher::Type::VIDEO
      expect_duration(destination_file, job[:duration])
    end
    input = job.inputs.first
    if input && MovieMasher::Type::MASH == input[:type]
      expect_dimensions(destination_file, output[:dimensions])
    end
    if MovieMasher::Type::VIDEO == output[:type]
      expect_fps(destination_file, output[:video_rate])
    end
  end
  destination_file
end
def spec_process_job_files(input_id, output = nil, destination = nil)
  output ||= 'video_h264'
  destination ||= 'file_log'
  job = spec_job(input_id, output, destination)
  (job ? spec_process_job(job) : nil)
end
def spec_source(src)
  if src && src.is_a?(String) && src.start_with?('magick/')
    src = MagickGenerator.generate(src)
  end
  src
end
RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.include(Rack::Test::Methods)
end
