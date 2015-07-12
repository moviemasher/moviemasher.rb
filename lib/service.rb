
module MovieMasher
	class Service
		ServicesDirectory = File.expand_path "#{__dir__}/../service"
		@@queues = Hash.new
		@@inits = Hash.new
		@@downloads = Hash.new
		@@uploads = Hash.new
		@@configuration = Hash.new
		def self.configure_services(config)
			@@configuration = config
		end
		def self.queues
			array = Array.new
			__service_names(:queue).each do |name|
				@@queues[name] = __create_service(name, :queue) unless @@queues[name]
				array << @@queues[name] if @@queues[name] and @@queues[name].configure(@@configuration)
			end
			array
		end
		def self.initer(type)
			@@inits[type] = __create_service type, :init unless @@inits[type]
			(@@inits[type] and @@inits[type].configure(@@configuration) ? @@inits[type] : nil)
		end
		def self.downloader(type)
			@@downloads[type] = __create_service type, :download unless @@downloads[type]
			(@@downloads[type] and @@downloads[type].configure(@@configuration) ? @@downloads[type] : nil)
		end
		def self.uploader(type)
			@@uploads[type] = __create_service type, :upload unless @@uploads[type]
			(@@uploads[type] and @@uploads[type].configure(@@configuration) ? @@uploads[type] : nil)
		end
		def self.query_parameters

		end
		def self.__create_service(name, kind = :queue)
			service = nil
			class_sym = "#{name.capitalize}#{kind.id2name.capitalize}Service".to_sym
			unless MovieMasher.const_defined? class_sym
				path = "#{ServicesDirectory}/#{kind.id2name}/#{name}.rb"
				require path if File.exists? path
			end
			if MovieMasher.const_defined? class_sym
				service = MovieMasher.const_get(class_sym).new
			end
			service
		end
		def self.__service_names(kind = :queue)
			Dir["#{ServicesDirectory}/#{kind.id2name}/*.rb"].map { | path | File.basename path, '.rb' }
		end
		def configuration
			@@configuration
		end
		def configure(config)
			true
		end
	end
	class InitService < Service
		def init

		end
	end
	class QueueService < Service
		def receive_job
			nil
		end
	end
	class DownloadService < Service
		def download(options)
			raise Error::Configuration.new "transfer service failed to override download method"
		end
	end
	class UploadService < Service
		def directory_files file
			uploading_directory = File.directory?(file)
			files = Array.new
			if uploading_directory then
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
		def upload(options)

		end
	end
end
