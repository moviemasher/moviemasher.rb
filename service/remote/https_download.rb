
require_relative 'http_download'

module MovieMasher
  # downloads assets via http securely
  class HttpsDownloadService < HttpDownloadService
    def secure
      true
    end
  end
end
