
require_relative 'helpers/clientside_aws'

describe File.basename(__FILE__) do
  before(:all) do
    @redis_pid = spec_start_redis
    @directory = MovieMasher.configuration[:download_directory]
    if @directory.to_s.empty?
      @directory = MovieMasher.configuration[:render_directory]
    end
  end
  after(:all) do
    spec_stop_redis(@redis_pid)
  end
  context '__cache_asset' do
    it 'correctly saves cached file when source is s3 object' do
      image_path = MagickGenerator.image_file
      image_input = {
        'id' => 'image_s3',
        'type' => 'image',
        'source' => {
          'type' => 's3',
          'bucket' => 'test',
          'path' => 'media/image',
          'name' => 'small-1x1',
          'extension' => 'png'
        }
      }

      job = spec_job_from_files(image_input)
      input = job[:inputs].first
      source = input[:source]
      file_name = "#{source[:name]}.#{source[:extension]}"
      source_frag = MovieMasher::Path.concat(source[:path], file_name)
      job_object = MovieMasher::Job.create(job)
      job_object.preflight
      upload_service = MovieMasher::Service.uploader(:s3)
      s3 = upload_service.__s3(MovieMasher::Source.new(source))
      s3.buckets.create(source[:bucket].to_s)
      bucket = s3.buckets[source[:bucket]]
      expect(File.exist?(image_path)).to be_truthy
      object = bucket.objects[source_frag]
      object.write(Pathname.new(image_path), content_type: 'image/png')
      input = job_object[:inputs].first
      path = MovieMasher::Asset.url_path(input.url)
      job_object.__cache_asset(input)
      expect(path).to eq MovieMasher::Asset.url_path(input[:input_url])
      expect(File.exist?(path)).to be_truthy
      expect(FileUtils.identical?(path, image_path)).to be_truthy
    end
  end
end
