module MovieMasher
	module Path
		Slash = '/'
		def self.add_slashes s
			add_slash_start(add_slash_end(s))
		end
		def self.add_slash_start s
			s = '' unless s
			s = "#{Slash}#{s}" unless s.start_with? Slash
			s
		end
		def self.add_slash_end s
			s = '' unless s
			s = "#{s}#{Slash}" unless s.end_with? Slash
			s
		end
		def self.strip_slashes s
			strip_slash_start(strip_slash_end(s))
		end
		def self.strip_slash_start s
			s = '' unless s
			s = s[1..-1] if s.start_with? Slash
			s
		end
		def self.strip_slash_end s
			s = '' unless s
			s = s[0..-2] if s.end_with? Slash
			s
		end
	end
end


