
require_relative 'http'

module MovieMasher
  # downloads assets via http securely
  class HttpsDownloadService < HttpDownloadService
    def secure
      true
    end
  end
end
