require_relative 'helpers/spec_helper'
require_relative '../lib/service'
describe File.basename(__FILE__) do
  before(:each) do
    spec_delete_all
    spec_create_bucket(@bucket)
    spec_create_queue(@queue)
  end

  before(:all) do
    @bucket = 'rspec'
    @queue = 'rspec'
    @img_output = {
      "type": 'image',
      "name": 'file.png',
      "dimensions": '100x100',
      "quality": '1'
    }
    @file_input = {
      "id": 'file_input',
      "type": 'image',
      "source": 'magick/lg-4x3.png'
    }
    @file_destination = {
      "type": 'file',
      "path": "#{DIR_LOCAL_POSTS}/output.png",
      "method": 'move'
    }
    @s3_input = {
      "id": 's3_input',
      "type": 'image',
      "source": {
        "type": 's3',
        "path": 'path/to',
        "bucket": @bucket,
        "name": 'input.png'
      }
    }
    @http_input = {
      "id": 'http_input',
      "type": 'image',
      "source": {
        "type": 'http',
        "path": 'posts/path/to',
        "host": 'http', # same as docker-compose service
        "port": '80', # exposed port (doesn't matter if mapped)
        "name": 'input.png'
      }
    }
    @https_input = {
      "id": 'https_input',
      "type": 'image',
      "source": 'https://moviemasher.com/media/img/mm-logo-200.png'
    }
    @s3_destination = {
      "type": 's3',
      "bucket": @bucket,
      "acl": 'private',
      "path": 'path/to'
    }
    @http_destination = {
      "type": 'http',
      "host": 'http', # same as docker-compose service
      "port": '80', # exposed port (doesn't matter if mapped)
      "path": 'php',
      "name": 'index.php'
    }
    @aws_config = {
      secret_access_key: '...', access_key_id: '...', region: 'us-east-1'
    }
    @directory = MovieMasher.configuration[:download_directory]
    if @directory.to_s.empty?
      @directory = MovieMasher.configuration[:render_directory]
    end
  end

  context 'when scanning configuration in config.yml' do
    it 's3 upload service returns expected aws_configuration' do
      service = MovieMasher::Service.instance(:upload, :s3)
      expect(service.aws_configuration).to eq @aws_config
    end
    it 'sqs queue service returns expected aws_configuration' do
      service = MovieMasher::Service.instance(:queue, :sqs)
      expect(service.aws_configuration).to eq @aws_config
    end
  end

  context "when scanning #{MovieMasher::Service::SERVICES_DIRECTORY}" do
    it 'services(:download) returns file, http, https, and s3' do
      services = MovieMasher::Service.services(:download)
      expect(services.map { |s| s[:name] }.sort).to eq %w[file http https s3]
    end
    it 'services(:queue) returns file and sqs' do
      services = MovieMasher::Service.services(:queue)
      expect(services.map { |s| s[:name] }.sort).to eq %w[file sqs]
    end
    it 'services(:upload) returns file, http, https, and s3' do
      services = MovieMasher::Service.services(:upload)
      expect(services.map { |s| s[:name] }.sort).to eq %w[file http https s3]
    end
  end

  context 'when creating Service instances' do
    it 'downloader(:file) returns instance of FileDownloadService' do
      instance = MovieMasher::Service.downloader(:file)
      expect(instance).to be_an_instance_of MovieMasher::FileDownloadService
      expect(instance).to be_a MovieMasher::Service
    end
    it 'downloader(:http) returns instance of HttpDownloadService' do
      instance = MovieMasher::Service.downloader(:http)
      expect(instance).to be_an_instance_of MovieMasher::HttpDownloadService
      expect(instance).to be_a MovieMasher::Service
    end
    it 'downloader(:s3) returns instance of S3DownloadService' do
      instance = MovieMasher::Service.downloader(:s3)
      expect(instance).to be_an_instance_of MovieMasher::S3DownloadService
      expect(instance).to be_a MovieMasher::Service
    end
    it 'queues returns both SqsQueueService and FileQueueService' do
      queues = MovieMasher::Service.queues
      expect(queues.count).to eq 2
      queues.each do |instance|
        is_class = instance.is_a?(MovieMasher::SqsQueueService)
        is_class ||= instance.is_a?(MovieMasher::FileQueueService)
        expect(is_class).to be_truthy
        expect(instance).to be_a MovieMasher::QueueService
        expect(instance).to be_a MovieMasher::Service
      end
    end
    it 'uploader(:file) returns instance of FileUploadService' do
      instance = MovieMasher::Service.uploader(:file)
      expect(instance).to be_an_instance_of MovieMasher::FileUploadService
      expect(instance).to be_a MovieMasher::Service
    end
    it 'uploader(:http) returns instance of HttpUploadService' do
      instance = MovieMasher::Service.uploader(:http)
      expect(instance).to be_an_instance_of MovieMasher::HttpUploadService
      expect(instance).to be_a MovieMasher::Service
    end
    it 'uploader(:s3) returns instance of S3UploadService' do
      instance = MovieMasher::Service.uploader(:s3)
      expect(instance).to be_an_instance_of MovieMasher::S3UploadService
      expect(instance).to be_a MovieMasher::Service
    end
  end

  context 'when uploading to file service' do
    it 'file input renders to file destination' do
      spec_process_files(@file_input, @img_output, @file_destination)
      expect_local_file('output.png')
    end
    it 'http input renders to file destination' do
      spec_put_file_http(MagickGenerator.image_file, 'path/to/input.png')
      spec_process_files(@http_input, @img_output, @file_destination)
      expect_local_file('output.png')
    end
    it 'https input renders to file destination' do
      spec_process_files(@https_input, @img_output, @file_destination)
      expect_local_file('output.png')
    end
    it 's3 input renders to file destination' do
      spec_put_file_s3(MagickGenerator.image_file, @bucket, 'path/to/input.png')
      spec_process_files(@s3_input, @img_output, @file_destination)
      expect_local_file('output.png')
    end
  end

  context 'when uploading to http service' do
    it 'file input renders to http destination' do
      spec_process_files(@file_input, @img_output, @http_destination)
      expect_http_file('file.png')
    end
    it 'http input renders to http destination' do
      spec_put_file_http(MagickGenerator.image_file, 'path/to/input.png')
      spec_process_files(@http_input, @img_output, @http_destination)
      expect_http_file('file.png')
    end
    it 'https input renders to http destination' do
      spec_process_files(@https_input, @img_output, @http_destination)
      expect_http_file('file.png')
    end
    it 's3 input renders to http destination' do
      spec_put_file_s3(MagickGenerator.image_file, @bucket, 'path/to/input.png')
      spec_process_files(@s3_input, @img_output, @http_destination)
      expect_http_file('file.png')
    end
  end

  context 'when uploading to s3 service' do
    it 'file input renders to s3 destination' do
      spec_process_files(@file_input, @img_output, @s3_destination)
      expect_s3_file(@bucket, 'path/to/file.png')
    end
    it 'http input renders to s3 destination' do
      spec_put_file_http(MagickGenerator.image_file, 'path/to/input.png')
      spec_process_files(@http_input, @img_output, @s3_destination)
      expect_s3_file(@bucket, 'path/to/file.png')
    end
    it 'https input renders to s3 destination' do
      spec_process_files(@https_input, @img_output, @s3_destination)
      expect_s3_file(@bucket, 'path/to/file.png')
    end
    it 's3 input renders to s3 destination' do
      spec_put_file_s3(MagickGenerator.image_file, @bucket, 'path/to/input.png')
      spec_process_files(@s3_input, @img_output, @s3_destination)
      expect_s3_file(@bucket, 'path/to/file.png')
    end
  end

  context 'when posting job to sqs queue' do
    it 'file input renders to file destination' do
      job = spec_job_files(@file_input, @img_output, @file_destination)
      spec_queue_job_sqs(spec_magick(job))
      MovieMasher.process_queues
      expect_local_file('output.png')
    end
    it 'http input renders to http destination' do
      spec_put_file_http(MagickGenerator.image_file, 'path/to/input.png')
      job = spec_job_files(@http_input, @img_output, @http_destination)
      spec_queue_job_sqs(spec_magick(job))
      MovieMasher.process_queues
      expect_http_file('file.png')
    end
    it 's3 input renders to s3 destination' do
      spec_put_file_s3(MagickGenerator.image_file, @bucket, 'path/to/input.png')
      job = spec_job_files(@s3_input, @img_output, @s3_destination)
      spec_queue_job_sqs(spec_magick(job))
      MovieMasher.process_queues
      expect_s3_file(@bucket, 'path/to/file.png')
    end
  end

  context 'when posting job to local queue' do
    it 'file input renders to file destination' do
      job = spec_job_files(@file_input, @img_output, @file_destination)
      spec_queue_job_file(spec_magick(job))
      MovieMasher.process_queues
      expect_local_file('output.png')
    end
    it 'http input renders to http destination' do
      spec_put_file_http(MagickGenerator.image_file, 'path/to/input.png')
      job = spec_job_files(@http_input, @img_output, @http_destination)
      spec_queue_job_file(spec_magick(job))
      MovieMasher.process_queues
      expect_http_file('file.png')
    end
    it 's3 input renders to s3 destination' do
      spec_put_file_s3(MagickGenerator.image_file, @bucket, 'path/to/input.png')
      job = spec_job_files(@s3_input, @img_output, @s3_destination)
      spec_queue_job_file(spec_magick(job))
      MovieMasher.process_queues
      expect_s3_file(@bucket, 'path/to/file.png')
    end
  end
end
