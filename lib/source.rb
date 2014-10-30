
module MovieMasher
# A Transfer object used for Input#source and Media#source, describing how to 
# retrieve an audio, image, video or mash JSON/YML file. 
#
# When building file paths, components will automatically have slashes inserted 
# between them as needed so trailing and leading slashes are optional. The 
# #extension will be populated and removed from #name if it exists there. 
#
# 	Source.create {
# 		:type => Transfer::TypeHttps,   # https://user:pass@example.com:444/media/video.mp4
# 		:user => 'user',
# 		:pass => 'pass',
# 		:host => 'example.com',
# 		:port => 444,
# 		:path => 'media/video.mp4'
# 	}
	class Source < Transfer
# Returns a new instance.
		def self.create hash
			Source.new hash
		end
		
		def extension; _get __method__; end
# String - Appended to file path after #name, with period inserted between.
		def extension=(value); _set __method__, value; end

		def name; _get __method__; end
# String - The full or basename of file appended to file path. If full, 
# #extension will be set and removed from value.
		def name=(value); _set __method__, value; end

	end
end