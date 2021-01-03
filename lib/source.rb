# frozen_string_literal: true

module MovieMasher
  # A Transfer object used for Input#source and Media#source, describing how to
  # retrieve an audio, image, video or mash JSON/YML file.
  #
  # When building file paths, components will automatically have slashes
  # inserted between them as needed so trailing and leading slashes are
  # optional. The #extension will be populated and removed from #name if it
  # exists there.
  #   # https://user:pass@example.com:444/media/video.mp4
  #   Source.create {
  #     type: Type::HTTPS,
  #     user: 'user',
  #     pass: 'pass',
  #     host: 'example.com',
  #     port: 444,
  #     path: 'media/video.mp4'
  #   }
  class Source < Transfer
    # Returns a new instance.
    def self.create(hash = nil)
      (hash.is_a?(Source) ? hash : Source.new(hash))
    end

    def self.create_if(hash)
      (hash ? create(hash) : nil)
    end

    def self.init_hash(hash = nil)
      hash ||= {}
      Hashable._init_key hash, :type, Type::FILE
      case hash[:type]
      when Type::FILE
        Hashable._init_key hash, :method, Method::SYMLINK
      when Type::HTTP
        Hashable._init_key hash, :method, Method::GET
      end
      Transfer.init_hash(hash)
    end

    def self.init_string(url)
      hash = {}
      uri = URI url
      hash[:type] = uri.scheme if uri.scheme #=> "http(s)"
      hash[:host] = uri.host if uri.host #=> "foo.com"
      hash[:path] = uri.path #=> "/posts"
      hash[:user] = uri.user if uri.user
      hash[:pass] = uri.password if uri.password
      hash[:port] = uri.port if uri.port
      hash[:parameters] = CGI.parse(uri.query) if uri.query
      hash
    end

    def extension
      _get __method__
    end

    # String - Appended to file path after #name, with period inserted between.
    def extension=(value)
      _set __method__, value
    end

    def initialize(hash_or_string = nil)
      if hash_or_string.is_a?(String)
        hash_or_string = self.class.init_string(hash_or_string)
      end
      self.class.init_hash hash_or_string
      super hash_or_string
    end

    def name
      _get __method__
    end

    # String - The full or basename of file appended to file path. If full,
    # #extension will be set and removed from value.
    def name=(value)
      _set __method__, value
    end
  end
end
