
require_relative 'helpers/spec_helper'

describe File.basename(__FILE__) do
	context "MovieMasher.formats" do
		it "true == start_with? 'File formats:'" do
			result = MovieMasher.formats
			#puts result
			expect(result.start_with? 'File formats:').to be_true
		end
	end
	context "MovieMasher.codecs" do
		it "true == start_with? 'Codecs:'" do
			result = MovieMasher.codecs
			#puts result
			expect(result.start_with? 'Codecs:').to be_true
		end
	end
end