def flush_cache_files(dir, gigs = nil)
	result = false
	gigs = 0 unless gigs
	if File.exists?(dir) then
		kbs = gigs * 1024 * 1024
		ds = flush_directory_size_kb(dir)
		#puts "flush_directory_size_kb #{dir} #{ds}"
	
		result = flush_cache_kb(dir, ds - kbs) if (ds > kbs)
	end
	result
end
def flush_cache_kb(dir, kbs_to_flush)
	cmd = "-d 1 #{dir}"
	result = MovieMasher.app_exec cmd, nil, nil, nil, 'du'
	if result then
		directories = Array.new
		lines = result.split "\n"
		lines.each do |line|
			next unless line and not line.empty?
			bits = line.split "\t"
			next if ((bits.length < 2) || (! bits[1]) || bits[1].empty?)
			next if (bits[1] == dir)
			dir = bits[1]
			next unless File.directory? dir
			dir += '/' unless dir.end_with?('/')
			cached = cache_get_info(dir, 'cached')
			# try to determine from modification time
			cached = File.mtime(dir) unless cached
			cached = 0 unless cached
			directories << {:cached => cached, :bits => bits}
		end
		unless directories.empty?
			directories.sort! { |a,b| a[:cached] <=> b[:cached] }				
			directories.each do |dir|
				FileUtils.rm_r dir[:bits][1]
				kbs_to_flush -= dir[:bits][0]
				break if (kbs_to_flush <= 0) 
			end
		end
	end
	(kbs_to_flush <= 0)
end
def flush_directory_size_kb(dir)
	size = 0
	cmd = "-s #{dir}"
	result = MovieMasher.app_exec cmd, nil, nil, nil, 'du'
	if result then
		result = result.split "\t"
		result = result.first
		size += result.to_i if result.to_i.to_s == result
	end
	size
end
