				
module MovieMasher
	class HttpUploadService < UploadService
		def upload options
			output = options[:output]
			file = options[:file]
			output_destination = options[:destination]
			output_content_type = output[:mime_type]
			destination_path = options[:path]
			url = "#{output_destination[:type]}://#{output_destination[:host]}"
			url += Path.add_slash_start destination_path
			uri = URI(url)
			uri.port = output_destination[:port].to_i if output_destination[:port]
			parameters = output_destination[:parameters]
			if parameters and parameters.is_a?(Hash) and not parameters.empty?
				scope = Hash.new
				scope[:job] = options[:job]
				scope[output.class_symbol] = output
				parameters = Marshal.load(Marshal.dump(parameters))
				Evaluate.object parameters, scope
				uri.query = URI.encode_www_form parameters
			end
			file_name = File.basename file
			io = File.open(file)
			raise Error::Object.new "could not open file #{file}" unless io
			upload_io = UploadIO.new(io, output_content_type, file_name)
			req = Net::HTTP::Post::Multipart.new(uri, "key" => destination_path, "file" => upload_io)
			raise Error::JobUpload.new "could not construct multipart POST request" unless req
			req.basic_auth(output_destination[:user], output_destination[:pass]) if output_destination[:user] and output_destination[:pass]
			res = Net::HTTP.start(uri.host, uri.port, :use_ssl => secure) do |http|
				result = http.request(req)
				raise Error::JobUpload.new "#{result.code} upload #{uri} response #{result.body}" if 200 <  result.code
			end
			io.close 
		end
		def secure
			false
		end
	end
end
