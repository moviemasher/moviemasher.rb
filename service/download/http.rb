				
module MovieMasher
	class HttpDownloadService < DownloadService

		def download options
			source = options[:source]
			cache_url_path = options[:path]
			uri = URI options[:asset][:input_url]
			uri.port = source[:port] if source[:port]
			parameters = source[:parameters]
			if parameters and parameters.is_a?(Hash) and not parameters.empty?
				scope = Hash.new
				scope[:job] = options[:job]
				scope[options[:asset].class_symbol] = options[:asset]
				parameters = Marshal.load(Marshal.dump(parameters))
				Evaluate.object parameters, scope
				uri.query = URI.encode_www_form parameters
			end
			req.basic_auth(source[:user], source[:pass]) if source[:user] and source[:pass]
			Net::HTTP.start(uri.host, uri.port, :use_ssl => secure) do |http|
				request = Net::HTTP::Get.new uri
				http.request request do |response|
					if '200' == response.code then
						File.open(cache_url_path, 'wb') do |io|
							response.read_body do |chunk|
								io.write chunk
							end
						end
						mime_type = response['content-type']
						Info.set(cache_url_path, 'Content-Type', mime_type) if mime_type
					else
						raise Error::JobInput.new "got #{response.code} response code from #{uri}"
					end
				end
			end
		end
		def secure
			false
		end
	end
end
