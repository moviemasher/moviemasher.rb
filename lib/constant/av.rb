
module MovieMasher
	module AV
		Audio = 'audio'
		Both = 'both'
		Neither = 'neither'
		Video = 'video'
		def self.includes? has, desired
			(Both == desired) or (Both == has) or (desired == has) 
		end
		def self.merge type1, type2
			return type1 unless type2 and type1 != type2
			Both
		end
	end
end