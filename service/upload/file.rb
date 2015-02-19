				
module MovieMasher
	class FileUploadService < UploadService
		def upload options
			#TODO: we should be using output, no??
			output = options[:output] 
			output_destination = options[:destination]
			destination_path = options[:path]
			file = options[:file]
			FileHelper.safe_path(File.dirname(destination_path))
			file = File.expand_path(file) unless file.start_with? '/'
			if File.exists? file
				destination_path = File.expand_path(destination_path) unless destination_path.start_with? '/'
				case output_destination[:method]
				when Method::Copy
					FileUtils.copy file, destination_path
				when Method::Move
					FileUtils.move file, destination_path
				else # Method::Symlink
					FileUtils.symlink file, destination_path
				end
				raise Error::JobUpload.new "could not #{output_destination[:method]} #{file} to #{destination_path}" unless File.exists? destination_path
			end
			output_destination[:file] = destination_path # for spec tests to find file...
		end
		def directory_files path
			[path]
		end
	end
end
