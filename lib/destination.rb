# frozen_string_literal: true

module MovieMasher
  # A Transfer object used as job's destination or output's destination
  # representing a remote host ready to accept rendered file(s).
  #
  #
  #   Destination.create {
  #     type: Type::HTTP,
  #     host: 'example.com', # http://example.com/cgi-bin/error.cgi?i=123
  #     path: 'cgi-bin/upload.cgi',
  #     parameters: {i: '{job.id}'}  # Scalar - job's id
  #   }
  class Destination < Transfer
    class << self
      # Returns a new instance.
      def create(hash = nil)
        (hash.is_a?(Destination) ? hash : new(hash))
      end

      def create_if(hash)
        (hash ? create(hash) : nil)
      end

      def init_hash(hash)
        Transfer.init_hash(hash)
      end
    end

    def error?
      return unless name.to_s.include?('/')

      "destination name contains slash - use path instead #{name}"
    end

    def upload(options)
      options[:destination] = self
      __service.upload(options)
    end

    def directory_files(file)
      __service.directory_files(file)
    end

    def __service
      service = Service.uploader(type)
      raise(Error::Configuration, "no #{type} upload service") unless service

      service
    end
  end
end
