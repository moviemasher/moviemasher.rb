
module MovieMasher
  # abstraction layer for initing, upload, download, queue services
  class Service
    SERVICES_DIRECTORY = File.expand_path("#{__dir__}/../service")
    class << self
      attr_accessor :__configuration
      attr_accessor :__cache
    end
    Service.__cache = {}
    Service.__configuration = {}
    def self.configure_services(config)
      Service.__configuration = config
    end
    def self.downloader(type)
      __service(:download, type)
    end
    def self.initer(type)
      __service(:init, type)
    end
    def self.queues
      array = []
      __service_names(:queue).each do |type|
        service = __service(:queue, type)
        array << service if service
      end
      array
    end
    def self.uploader(type)
      __service(:upload, type)
    end
    def self.__create_service(name, kind = :queue)
      service = nil
      class_sym = "#{name.capitalize}#{kind.id2name.capitalize}Service".to_sym
      unless MovieMasher.const_defined?(class_sym)
        path = "#{SERVICES_DIRECTORY}/#{kind.id2name}/#{name}.rb"
        require path if File.exist?(path)
      end
      if MovieMasher.const_defined?(class_sym)
        service = MovieMasher.const_get(class_sym).new
      end
      service
    end
    def self.__service(kind, type)
      Service.__cache[kind] ||= {}
      if Service.__cache[kind][type].nil?
        service = __create_service(type, kind)
        Service.__cache[kind][type] =
          if service && service.configure(Service.__configuration)
            service
          else
            false
          end
      end
      Service.__cache[kind][type]
    end
    def self.__service_names(kind = :queue)
      Dir["#{SERVICES_DIRECTORY}/#{kind.id2name}/*.rb"].map do |path|
        File.basename(path, '.rb')
      end
    end
    def configuration
      Service.__configuration
    end
    def configure(*)
      true
    end
  end
  # base class for init service
  class InitService < Service
    def init
    end
  end
  # base class for queue service
  class QueueService < Service
    def receive_job
      nil
    end
  end
  # base class for downloader service
  class DownloadService < Service
    def download(*)
      raise(Error::Configuration, 'download method not overridden')
    end
  end
  # base class for uploader service
  class UploadService < Service
    def directory_files(file)
      uploading_directory = File.directory?(file)
      files = []
      if uploading_directory
        file = Path.add_slash_end file
        Dir.entries(file).each do |f|
          f = file + f
          files << f unless File.directory?(f)
        end
      else
        files << file
      end
      files
    end
    def upload(*)
    end
  end
end
