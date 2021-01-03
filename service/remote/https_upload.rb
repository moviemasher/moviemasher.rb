# frozen_string_literal: true

require_relative 'http_upload'

module MovieMasher
  # uploads via http securely
  class HttpsUploadService < HttpUploadService
    def secure
      true
    end
  end
end
