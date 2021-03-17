# frozen_string_literal: true

module MovieMasher
  # Base class for Callback and Source as well as used directly to
  # resolve Input and Output relative paths to a specific location.
  #
  # There are three basic types of transfers - Type::FILE, Type::HTTP and
  # Type::S3 representing locations on the local drive, remote web servers and
  # AWS S3 buckets respectively. Type::FILE transfers can either move, copy or
  # create symbolic links for files. Type::HTTP (and Type::HTTPS) transfers can
  # supply authenticating #parameters and Type::S3 transfers will use access
  # keys provided in the configuration or any mechanism supported by aws-sdk
  # (environmental variables, instance roles, etc.).
  #
  # When building file paths, #directory and #path will automatically have
  # slashes inserted between them as needed so trailing and leading slashes are
  # optional.
  class Transfer < Hashable
    class << self
      # Returns a new instance.
      def create(hash = nil)
        # puts "Transfer.create #{hash}"
        (hash.is_a?(Transfer) ? hash : Transfer.new(hash))
      end

      def create_if(hash)
        (hash ? create(hash) : nil)
      end

      def file(mode, path, out_file)
        path = File.expand_path(path) unless path.start_with?('/')
        return unless File.exist?(path)

        out_file = File.expand_path(out_file) unless out_file.start_with?('/')
        case mode
        when Method::COPY
          FileUtils.copy(path, out_file)
        when Method::MOVE
          FileUtils.move(path, out_file)
        else # Method::SYMLINK
          FileUtils.symlink(path, out_file)
        end
        return if File.exist?(out_file)

        raise(Error::JobUpload, "could not #{mode} #{path} to #{out_file}")
      end

      def init_hash(hash)
        Hashable._init_key hash, :type, Type::FILE
        case hash[:type]
        when Type::S3
          Hashable._init_key(hash, :acl, 'public-read')
        when Type::FILE
          Hashable._init_key(hash, :method, Method::MOVE)
        when Type::HTTP
          Hashable._init_key(hash, :method, Method::POST)
        end
        hash
      end
    end

    def bucket
      _get __method__
    end

    # String - Name of AWS S3 bucket where file is stored.
    # Types - Just Type::S3.
    def bucket=(value)
      _set __method__, value
    end

    def directory
      _get __method__
    end

    # String - Added to URL after #directory, before #name, slashed.
    # Default - Nil means do not add to URL.
    # Types - Type::HTTP and Type::HTTPS.
    def directory=(value)
      _set __method__, value
    end

    def directory_path
      Path.concat(directory, path)
    end

    def error?
      nil
    end

    def extension
      _get __method__
    end

    # String - Appended to file path after #name, with period inserted between.
    def extension=(value)
      _set __method__, value
    end

    def file_name
      fn = Path.strip_slashes name
      fn += ".#{extension}" if extension
      fn
    end

    def full_path
      Path.concat directory_path, file_name
      # puts "#{self.class.name}#full_path #{fp}"
    end

    def host
      _get __method__
    end

    # String - Remote server name or IP address where file is stored.
    # Types - Type::HTTP and Type::HTTPS.
    def host=(value)
      _set __method__, value
    end

    def initialize(hash = nil)
      self.class.init_hash hash
      super
    end

    def method
      _get __method__
    end

    # String - How to retrieve the file.
    # Constant - Method::COPY, Method::MOVE or Method::SYMLINK.
    # Default - Method::SYMLINK
    # Types - Just Type::FILE.
    def method=(value)
      _set __method__, value
    end

    def name
      _get __method__
    end

    # String - The full or basename of file appended to file path. If full,
    # #extension will be set and removed from value.
    def name=(value)
      _set __method__, value
    end

    def parameters
      _get __method__
    end

    # Hash - Query string parameters to send with request for file. The values
    # are evaluated, with job and input in scope.
    # Default - Nil means no query string used.
    # Types - Type::HTTP and Type::HTTPS.
    def parameters=(value)
      _set __method__, value
    end

    def pass
      _get __method__
    end

    # String - Password for standard HTTP authentication.
    # Default - Nil means do not provide authenticating details.
    # Types - Type::HTTP and Type::HTTPS.
    def pass=(value)
      _set __method__, value
    end

    def path
      _get __method__
    end

    # String - Added to URL after #directory, before #name, slashed.
    # Default - Nil means do not add to URL.
    # Types - Type::HTTP and Type::HTTPS.
    def path=(value)
      _set __method__, value
    end

    def port
      _get __method__
    end

    # Integer - Port number to contact #host on.
    # Constant - Method::COPY, Method::MOVE or Method::SYMLINK.
    # Default - Nil means standard port for #type.
    # Types - Type::HTTP and Type::HTTPS.
    def port=(value)
      _set __method__, value
    end

    def self.query_string(transfer, job)
      parameters = transfer[:parameters]
      if parameters.is_a?(Hash) && !parameters.empty?
        parameters = Marshal.load(Marshal.dump(parameters))
        Evaluate.object(parameters, job: job, transfer: transfer)
        parameters = URI.encode_www_form(parameters)
      end
      parameters
    end

    def region
      _get __method__
    end

    # String - Global AWS region code.
    # Default - Nil means us-east-1 standard region.
    # Types - Just Type::S3.
    def region=(value)
      _set __method__, value
    end

    def relative?
      return false if Type::S3 == type
      return false if host && !host.empty?

      is_file = (Type::FILE == type)
      !(is_file && full_path.start_with?('/') && File.exist?(full_path))
    end

    def type
      _get __method__
    end

    # String - The kind of transfer.
    # Constant - Type::FILE, Type::HTTP, Type::HTTPS or Type::S3.
    # Default - Type::FILE
    def type=(value)
      _set __method__, value
    end

    def url
      u = @hash[:url]
      unless u
        u = ''
        case type
        when Type::HTTP, Type::HTTPS
          unless host.to_s.empty?
            u += "#{type}://#{host}"
            u += __unless_empty(port, ":#{port}")
          end
          u = Path.concat(u, full_path)
        when Type::S3
          u += __unless_empty(bucket, "#{bucket}.")
          u += 's3'
          u += __unless_empty(region, "-#{region}")
          u += '.amazonaws.com'
          u = Path.concat(u, full_path)
        when Type::FILE
          u = full_path
        end
      end
      # puts "#{self.class.name}#url #{u}"
      u
    end

    def user
      _get __method__
    end

    # String - Username for standard HTTP authentication.
    # Default - Nil means do not provide authenticating details.
    # Types - Type::HTTP and Type::HTTPS.
    def user=(value)
      _set __method__, value
    end

    def __unless_empty(could_be_empty, string)
      (could_be_empty.to_s.empty? ? '' : string)
    end
  end
end
