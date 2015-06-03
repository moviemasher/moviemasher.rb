
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
	class Transfer < Hashable
		TypeFile = 'file'
		TypeHttp = 'http'
		TypeHttps = 'https'
		TypeS3 = 's3'		
# Returns a new instance.
		def self.create hash = nil
			#puts "Transfer.create #{hash}"
			(hash.is_a?(Transfer) ? hash : Transfer.new(hash))
		end
		def self.create_if hash
			(hash ? create(hash) : nil)
		end
		def self.init_hash hash
			Hashable._init_key hash, :type, Transfer::TypeFile
			case hash[:type]
			when Transfer::TypeS3
				Hashable._init_key hash, :acl, 'public-read' 
			when Transfer::TypeFile
				Hashable._init_key hash, :method, Method::Move 
			when Transfer::TypeHttp
				Hashable._init_key hash, :method, Method::Post 
			end
			hash
		end
		
		def bucket
			_get __method__
		end
# String - Name of AWS S3 bucket where file is stored.
# Types - Just TypeS3.
		def bucket=(value)
			_set __method__, value
		end
	
		def directory
			_get __method__
		end
# String - Added to URL after #directory and before #name, with slash on either side.
# Default - Nil means do not add to URL.
# Types - TypeHttp and TypeHttps.
		def directory=(value)
			_set __method__, value
		end

		def directory_path
			dp = Path.concat directory, path
		  puts "#{self.class.name}#directory_path #{dp}\ndirectory: #{directory}\npath: #{path}"
			dp
		end
		def error?
			nil
		end
		def extension
			_get __method__
		end
# String - Appended to file path after #name, with period inserted between.
		def extension=(value)
			_set __method__, value
		end
		def file_name
			fn = Path.strip_slashes name
			fn += '.' + extension if extension
			fn
		end
		def full_path 
			fp = Path.concat directory_path, file_name
			puts "#{self.class.name}#full_path #{fp}"
			fp
		end

		
		def host
			_get __method__
		end
# String - Remote server name or IP address where file is stored.
# Types - TypeHttp and TypeHttps.
		def host=(value)
			_set __method__, value
		end
	
		def initialize hash = nil
			self.class.init_hash hash
			super
		end
		
		def method
			_get __method__
		end
# String - How to retrieve the file.
# Constant - Method::Copy, Method::Move or Method::Symlink.
# Default - Method::Symlink
# Types - Just TypeFile.
		def method=(value)
			_set __method__, value
		end

		def name
			_get __method__
		end
# String - The full or basename of file appended to file path. If full, 
# #extension will be set and removed from value.
		def name=(value)
			_set __method__, value
		end
	
		def parameters
			_get __method__
		end
# Hash - Query string parameters to send with request for file. The values are
# evaluated, with Job and Input in scope.
# Default - Nil means no query string used.
# Types - TypeHttp and TypeHttps.
		def parameters=(value)
			_set __method__, value
		end
	
		def pass
			_get __method__
		end
# String - Password for standard HTTP authentication.
# Default - Nil means do not provide authenticating details. 
# Types - TypeHttp and TypeHttps.
		def pass=(value)
			_set __method__, value
		end

		def path
			_get __method__
		end
# String - Added to URL after #directory and before #name, with slash on either side.
# Default - Nil means do not add to URL.
# Types - TypeHttp and TypeHttps.
		def path=(value)
			_set __method__, value
		end

	def port
			_get __method__
		end
# Integer - Port number to contact #host on.
# Constant - Method::Copy, Method::Move or Method::Symlink.
# Default - Nil means standard port for #type.
# Types - TypeHttp and TypeHttps.
		def port=(value)
			_set __method__, value
		end

		def region
			_get __method__
		end
# String - Global AWS geographical region code.
# Default - Nil means us-east-1 standard region.
# Types - Just TypeS3.
		def region=(value)
			_set __method__, value
		end
		
		def relative? 
			return false if Transfer::TypeS3 == type
			return false if host and not host.empty?
			return false if Transfer::TypeFile == type and full_path.start_with?('/') and File.exists?(full_path)
			true
		end
		def type
			_get __method__
		end
# String - The kind of transfer.
# Constant - TypeFile, TypeHttp, TypeHttps or TypeS3.
# Default - TypeFile
		def type=(value)
			_set __method__, value
		end
	
		def url 
			u = @hash[:url]
			unless u
				u = ''
				case type
				when Transfer::TypeHttp, Transfer::TypeHttps
					if host and not host.empty?
						u += "#{type}://#{host}"
						u += ":#{port}" if port and not port.to_s.empty?
					end
					u = Path.concat(u, full_path)
				when Transfer::TypeS3
					u += "#{bucket}." if bucket and not bucket.empty?
					u += 's3'
					u += "-#{region}" if region and not region.empty?
					u += '.amazonaws.com'
					u = Path.concat(u, full_path)
				when Transfer::TypeFile
					u = full_path
				end
			end
			puts "#{self.class.name}#url #{u}"
			u
		end
		
		def user
			_get __method__
		end
# String - Username for standard HTTP authentication.
# Default - Nil means do not provide authenticating details. 
# Types - TypeHttp and TypeHttps.
		def user=(value)
			_set __method__, value
		end

	end
end
