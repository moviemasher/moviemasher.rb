
module MovieMasher
# Base class for Callback and Source as well as used directly to resolve 
# Input and Output relative paths to a specific location. 
#
# There are three basic types of transfers - TypeFile, TypeHttp and TypeS3 
# representing locations on the local drive, remote web servers and AWS S3 
# buckets respectively. TypeFile transfers can either move, copy or create 
# symbolic links for files. TypeHttp (and TypeHttps) transfers can supply 
# authenticating #parameters and TypeS3 transfers will use access keys provided 
# in the configuration or any mechanism supported by aws-sdk (environmental 
# variables, instance roles, etc.). 
# 
# When building file paths, #directory and #path will automatically have slashes 
# inserted between them as needed so trailing and leading slashes are optional. 
	class Transfer
		include Hashable
		TypeFile = 'file'
		TypeHttp = 'http'
		TypeHttps = 'https'
		TypeS3 = 's3'		
# Returns a new instance.
		def self.create hash
			Transfer.new hash
		end

		def bucket; _get __method__; end
# String - Name of AWS S3 bucket where file is stored.
# Types - Just TypeS3.
		def bucket=(value); _set __method__, value; end
	
		def directory; _get __method__; end
# String - Added to URL after #directory and before #name, with slash on either side.
# Default - Nil means do not add to URL.
# Types - TypeHttp and TypeHttps.
		def directory=(value); _set __method__, value; end

		def host; _get __method__; end
# String - Remote server name or IP address where file is stored.
# Types - TypeHttp and TypeHttps.
		def host=(value); _set __method__, value; end
	
		def method; _get __method__; end
# String - How to retrieve the file.
# Constant - Method::Copy, Method::Move or Method::Symlink.
# Default - Method::Symlink
# Types - Just TypeFile.
		def method=(value); _set __method__, value; end
	
		def parameters; _get __method__; end
# Hash - Query string parameters to send with request for file. The values are
# evaluated, with Job and Input in scope.
# Default - Nil means no query string used.
# Types - TypeHttp and TypeHttps.
		def parameters=(value); _set __method__, value; end
	
		def pass; _get __method__; end
# String - Password for standard HTTP authentication.
# Default - Nil means do not provide authenticating details. 
# Types - TypeHttp and TypeHttps.
		def pass=(value); _set __method__, value; end

		def path; _get __method__; end
# String - Added to URL after #directory and before #name, with slash on either side.
# Default - Nil means do not add to URL.
# Types - TypeHttp and TypeHttps.
		def path=(value); _set __method__, value; end

	def port; _get __method__; end
# Integer - Port number to contact #host on.
# Constant - Method::Copy, Method::Move or Method::Symlink.
# Default - Nil means standard port for #type.
# Types - TypeHttp and TypeHttps.
		def port=(value); _set __method__, value; end

		def region; _get __method__; end
# String - Global AWS geographical region code.
# Default - Nil means us-east-1 standard region.
# Types - Just TypeS3.
		def region=(value); _set __method__, value; end
	
		def type; _get __method__; end
# String - The kind of transfer.
# Constant - TypeFile, TypeHttp, TypeHttps or TypeS3.
# Default - TypeFile
		def type=(value); _set __method__, value; end

		def user; _get __method__; end
# String - Username for standard HTTP authentication.
# Default - Nil means do not provide authenticating details. 
# Types - TypeHttp and TypeHttps.
		def user=(value); _set __method__, value; end

	end
end