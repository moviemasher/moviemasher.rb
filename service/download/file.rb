				
module MovieMasher
	class FileDownloadService < DownloadService
		def download options
			cache_url_path = options[:path]
			source_path = options[:asset][:input_url].dup
			source_path['file://'] = '' if source_path.start_with?('file://');
			source_path = File.expand_path(source_path) unless source_path.start_with? '/'
			raise Error::JobInput.new "file does not exist #{source_path}" unless File.exists? source_path
			cache_url_path = File.expand_path(cache_url_path) unless cache_url_path.start_with? '/'
			case options[:source][:method]
			when Method::Copy
				FileUtils.copy source_path, cache_url_path
			when Method::Move
				FileUtils.move source_path, cache_url_path
			else # Method::Symlink
				FileUtils.symlink source_path, cache_url_path
			end
			raise Error::JobInput.new "could not #{options[:source][:method]} #{source_path} to #{cache_url_path}" unless File.size? cache_url_path
		end
	end
end
