
module MovieMasher
  # uploads via http
  class HttpUploadService < UploadService
    def upload(options)
      output = options[:output]
      file = options[:file]
      output_destination = options[:destination]
      output_content_type = output[:mime_type]
      path = options[:path]
      url = "#{output_destination[:type]}://#{output_destination[:host]}"
      url += Path.add_slash_start(path)
      uri = URI(url)
      uri.port = output_destination[:port].to_i if output_destination[:port]
      parameters = output_destination[:parameters]
      if parameters && parameters.is_a?(Hash) && !parameters.empty?
        scope = {}
        scope[:job] = options[:job]
        scope[output.class_symbol] = output
        parameters = Marshal.load(Marshal.dump(parameters))
        Evaluate.object parameters, scope
        uri.query = URI.encode_www_form parameters
      end
      file_name = File.basename file
      io = File.open(file)
      raise(Error::Object, "could not open file #{file}") unless io
      upload_io = UploadIO.new(io, output_content_type, file_name)
      req = Net::HTTP::Post::Multipart.new(uri, key: path, file: upload_io)
      unless req
        raise(Error::JobUpload, 'could not construct multipart POST request')
      end
      if output_destination[:user] && output_destination[:pass]
        req.basic_auth(output_destination[:user], output_destination[:pass])
      end
      Net::HTTP.start(uri.host, uri.port, use_ssl: secure) do |http|
        result = http.request(req)
        if 200 < result.code
          msg = "#{result.code} upload #{uri} response #{result.body}"
          raise(Error::JobUpload, msg)
        end
      end
      io.close
    end
    def secure
      false
    end
  end
end
