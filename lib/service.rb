
module MovieMasher
  # abstraction layer for initing, upload, download, queue services
  class Service
    SERVICES_DIRECTORY = File.expand_path("#{__dir__}/../service")
    class << self
      attr_accessor :__configuration
      attr_accessor :__instances
      attr_accessor :__services
    end
    Service.__configuration = {}
    Service.__instances = {}
    Service.__services = {}
    def self.configure_services(config)
      Service.__configuration = config
    end
    def self.downloader(type)
      instance(:download, type)
    end
    def self.initer(type)
      instance(:init, type)
    end
    def self.queues
      array = []
      services(:queue).each do |hash|
        type = hash[:name]
        s = instance(:queue, type)
        array << s if s
      end
      array
    end
    def self.services(kind = nil)
      kind_nil = kind.nil?
      kinds = kind_nil ? [:queue, :upload, :download, :init] : [kind.to_sym]
      kinds.each do |kind_sym|
        Service.__services[kind_sym] ||= __scan_for_services(kind_sym)
      end
      kind_nil ? Service.__services : Service.__services[kind.to_sym]
    end
    def self.uploader(type)
      instance(:upload, type)
    end
    def self.__create_service(name, kind = :queue)
      s = nil
      return s if Service.__configuration[:disable_local] && 'file' == name.to_s
      service_config = services(kind).find{ |s| s[:name] == name.to_s }
      if service_config
        class_sym = service_config[:sym]
        unless MovieMasher.const_defined?(class_sym)
          path = service_config[:path]
          require path if File.exist?(path)
        end
        if MovieMasher.const_defined?(class_sym)
          s = MovieMasher.const_get(class_sym).new
        end
      end
      s
    end
    def self.__scan_for_services(kind)
      kind_fragment = "_#{kind.id2name}"
      Dir["#{SERVICES_DIRECTORY}/*/*#{kind_fragment}.rb"].map do |path|
        name = File.basename(path, '.rb')
        name[kind_fragment] = ''
        {
          name: name, path: path,
          sym: "#{name.capitalize}#{kind.id2name.capitalize}Service".to_sym
        }
      end
    end
    def self.instance(kind, type)
      Service.__instances[kind] ||= {}
      if Service.__instances[kind][type].nil?
        s = __create_service(type, kind)
        Service.__instances[kind][type] =
          if s && s.configure(Service.__configuration)
            s
          else
            false
          end
      end
      Service.__instances[kind][type]
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
