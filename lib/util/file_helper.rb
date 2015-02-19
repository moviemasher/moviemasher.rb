module MovieMasher
	module FileHelper
		def self.safe_path path, mod = nil
			options = Hash.new
			mod = MovieMasher.configuration[:chmod_directory_new] if mod.nil?
			if mod
				mod = mod.to_i(8) if mod.is_a? String
				options[:mode] = mod 
			end
			FileUtils.makedirs path, options
		end
	end
end
