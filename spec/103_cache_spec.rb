
require_relative 'helpers/spec_helper'

describe File.basename(__FILE__) do
	context "__cache_input" do
		it "correctly saves cached file when source is file object" do
			job = hash_keys_to_symbols!(spec_job_simple 'image_file')
			input = job[:inputs].first
			source = input[:source]
			source[:directory] = __dir__
			path = MovieMasher.__cache_input input
			url = "#{source[:type]}://#{__dir__}/#{source[:path]}/#{source[:name]}.#{source[:extension]}"
			url = MovieMasher.__hash url
			expect(path).to eq "#{MovieMasher.configuration[:dir_cache]}#{url}/cached.#{source[:extension]}"
			expect(File.exists? path).to be_true
			expect(File.symlink? path).to be_true
		end
	end
end