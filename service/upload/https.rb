
require_relative 'http'

module MovieMasher
  # uploads via http securely
  class HttpsUploadService < HttpUploadService
    def secure
      true
    end
  end
end
