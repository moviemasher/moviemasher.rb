module MovieMasher
	module Path
		Slash = '/'
		def self.add_slashes s
			add_slash_start(add_slash_end(s))
		end
		def self.add_slash_end s
			s = '' unless s
			s = "#{s}#{Slash}" unless s.end_with? Slash
			s
		end
		def self.add_slash_start s
			s = '' unless s
			s = "#{Slash}#{s}" unless s.start_with? Slash
			s
		end
		def self.concat s1, s2
			s1 = '' unless s1
			s2 = '' unless s2
			if s1.empty? or s2.empty?
				s1 += s2
			else
				s1 = add_slash_end(s1) + strip_slash_start(s2)
			end
			s1
		end
		def self.strip_slashes s
			strip_slash_start(strip_slash_end(s))
		end
		def self.strip_slash_end s
			s = '' unless s
			s = s[0..-2] if s.end_with? Slash
			s
		end
		def self.strip_slash_start s
			s = '' unless s
			s = s[1..-1] if s.start_with? Slash
			s
		end
	end
end


