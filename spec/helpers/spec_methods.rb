
def spec_callback_file(job)
  callback = job.callbacks.first
  (callback ? callback[:callback_file] : nil)
end
def spec_create_bucket(bucket_name)
  bucket = nil
  spec_retry_aws do
    bucket = spec_s3_resource.bucket(bucket_name)
    if bucket.exists?
      # puts "spec s3 bucket #{bucket_name} exists!"
    else
      bucket.create
      # puts "spec created s3 bucket #{bucket_name}"
    end
    bucket
  end
  bucket
end
def spec_create_queue(queue_name, **options)
  queue = nil
  spec_retry_aws do
    queue = spec_sqs_client.create_queue(
      queue_name: queue_name, attributes: options
    )
    # puts "spec created sqs queue #{queue_name}"
  end
  queue
end
def spec_delete_all
  spec_delete_files
  spec_delete_http
  spec_delete_s3
  spec_delete_queues
end
def spec_delete_files
  Dir["#{DIR_LOCAL_POSTS}/*"].each do |file|
    FileUtils.rm_r(file)
  end
end
def spec_delete_http
  Dir["#{DIR_HTTP_POSTS}/*"].each do |file|
    unless 'README.txt' == File.basename(file)
      # puts "spec deleting http file #{file}"
      FileUtils.rm_r(file)
    end
  end
end
def spec_sqs_service
  MovieMasher::Service.instance(:queue, :sqs)
end
def spec_sqs_client
  spec_sqs_service.sqs_client
end
def spec_delete_queues
  spec_retry_aws do
    spec_sqs_client.list_queues.queue_urls.each do |queue_url|
      # puts "spec deleting sqs queue #{queue_url}"
      spec_sqs_client.delete_queue(queue_url: queue_url)
    end
  end
end
def spec_s3_client
  MovieMasher::Service.instance(:upload, :s3).s3_client
end
def spec_s3_resource
  MovieMasher::Service.instance(:upload, :s3).s3_resource
end
def spec_delete_s3
  spec_retry_aws do
    spec_s3_client.list_buckets.buckets.each do |bucket|
      bucket_resource = spec_s3_resource.bucket(bucket.name)
      bucket_resource.objects.each do |object|
        # puts "spec deleting object s3://#{bucket.name}/#{object.key}"
        object.delete
      end
      # puts "spec deleting s3 bucket #{bucket.name}"
      bucket_resource.delete
    end
  end
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
  rendered_video_path = spec_process_job(job)
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
  job_data
end
def spec_job_files(input_id = nil, output = nil, destination = nil)
  job_data = spec_job_from_files(input_id, output, destination)
  unless job_data[:id]
    input = job_data[:inputs].first
    job_data[:id] = input[:id] if input
  end
  job_data
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
def spec_process(job)
  spec_magick(job)
  MovieMasher.process(MovieMasher::Job.create(job))
end
def spec_process_files(input_id, output = nil, destination = nil)
  spec_process(spec_job_files(input_id, output, destination))
end
def spec_process_job(job, expect_error = nil)
  return nil unless job
  spec_magick(job)
  job = MovieMasher.process(job)
  if job[:error] && !expect_error
    puts job[:error]
    puts job[:commands]
  end
  puts job[:error] if job[:error] && !job[:error] != !expect_error
  expect(!job[:error]).to eq !expect_error
  destination_file = spec_output(job)
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
  spec_process_job(spec_job(input_id, output, destination))
end
def spec_put_file_http(file_path, key)
  full_path = "#{DIR_HTTP_POSTS}/#{key}"
  MovieMasher::FileHelper.safe_path(File.dirname(full_path))
  FileUtils.mv(file_path, full_path)
end
def spec_put_file_s3(file_path, bucket, key)
  bucket_options = { acl: 'public-read', key: key, bucket: bucket }
  File.open(file_path, 'rb') do |file|
    bucket_options[:body] = file
    spec_s3_client.put_object(bucket_options)
  end
end
def spec_retry_aws
  yield
rescue StandardError => e
  puts "spec waiting for localstack to start: #{e.message}"
  retry
end
def spec_queue_job_file(job_hash)
  job_hash[:log_level] = 'info'
  path = MovieMasher.configuration[:queue_directory]
  path = MovieMasher::Path.add_slash_start(path)
  path = MovieMasher::Path.concat(path, "#{SecureRandom.uuid}.json")
  File.write(path, job_hash.to_json)
end
def spec_queue_job_sqs(job_hash)
  job_hash[:log_level] = 'info'
  spec_sqs_client.send_message(
    queue_url: spec_sqs_service.queue_url, message_body: job_hash.to_json
  )
end
def spec_source(src)
  if src && src.is_a?(String) && src.start_with?('magick/')
    src = MagickGenerator.generate(src)
  end
  src
end
