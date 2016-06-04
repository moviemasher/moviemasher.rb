
module MovieMasher
  # A Transfer object used as Job#destination or Output#destination
  # representing a remote host ready to accept rendered file(s).
  #
  #
  #   Destination.create {
  #     type: Type::HTTP,
  #     host: 'example.com', # http://example.com/cgi-bin/error.cgi?i=123
  #     path: 'cgi-bin/upload.cgi',
  #     parameters: {i: '{job.id}'}  # Scalar - Job#id
  #   }
  class Destination < Transfer
    # Returns a new instance.
    def self.create(hash = nil)
      (hash.is_a?(Destination) ? hash : new(hash))
    end
    def self.create_if(hash)
      (hash ? create(hash) : nil)
    end
    def self.init_hash(hash)
      Transfer.init_hash(hash)
    end
    def error?
      if name.to_s.include?('/')
        "destination name contains slash - use path instead #{name}"
      end
    end
    def upload(options)
      transfer_service = Service.uploader(type)
      unless transfer_service
        raise(Error::Configuration, "no upload service #{type}")
      end
      options[:destination] = self
      transfer_service.upload(options)
    end
    def directory_files(file)
      transfer_service = Service.uploader(type)
      unless transfer_service
        raise(Error::Configuration, "no upload service #{type}")
      end
      transfer_service.directory_files(file)
    end
  end
end
