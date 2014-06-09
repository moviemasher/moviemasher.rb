
require_relative 'spec_helper'

describe MovieMasher do
	context ".formats" do
		it "true == start_with? 'File formats:'" do
			result = MovieMasher.formats
			#puts result
			expect(result.start_with? 'File formats:').to be_true
		end
	end
	context ".codecs" do
		it "true == start_with? 'Codecs:'" do
			result = MovieMasher.codecs
			#puts result
			expect(result.start_with? 'Codecs:').to be_true
		end
	end
end