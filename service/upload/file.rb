
module MovieMasher
  # 'uploads' within the local file system
  class FileUploadService < UploadService
    def upload(options)
      output_destination = options[:destination]
      path = options[:path]
      file = options[:file]
      FileHelper.safe_path(File.dirname(path))
      file = File.expand_path(file) unless file.start_with? '/'
      if File.exist?(file)
        path = File.expand_path(path) unless path.start_with? '/'
        case output_destination[:method]
        when Method::COPY
          FileUtils.copy(file, path)
        when Method::MOVE
          FileUtils.move(file, path)
        else # Method::SYMLINK
          FileUtils.symlink(file, path)
        end
        unless File.exist?(path)
          msg = "could not #{output_destination[:method]} #{file} to #{path}"
          raise(Error::JobUpload, msg)
        end
      end
      output_destination[:file] = path # for spec tests to find file...
    end
    def directory_files(path)
      [path]
    end
  end
end
