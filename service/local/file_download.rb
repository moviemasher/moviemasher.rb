# frozen_string_literal: true

module MovieMasher
  # 'downloads' assets via local file system
  class FileDownloadService < DownloadService
    def download(options)
      cache_url_path = options[:path]
      source_path = options[:asset][:input_url].dup
      source_path['file://'] = '' if source_path.start_with?('file://')
      unless source_path.start_with?('/')
        source_path = File.expand_path(source_path)
      end
      unless File.exist?(source_path)
        raise(Error::JobInput, "file does not exist #{source_path}")
      end

      unless cache_url_path.start_with?('/')
        cache_url_path = File.expand_path(cache_url_path)
      end
      method = options[:source][:method]
      case method
      when Method::COPY
        FileUtils.copy(source_path, cache_url_path)
      when Method::MOVE
        FileUtils.move(source_path, cache_url_path)
      else # Method::SYMLINK
        FileUtils.symlink(source_path, cache_url_path)
      end
      return if File.size?(cache_url_path)

      msg = "could not #{method} #{source_path} to #{cache_url_path}"
      raise(Error::JobInput, msg)
    end
  end
end
