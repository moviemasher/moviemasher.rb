
#ENV['RACK_ENV'] = 'production' unless ENV['RACK_ENV']

require_relative 'lib/moviemasher'

configuration = YAML::load(File.open(MovieMasher::PathConfiguration))
user_data_file = "#{__dir__}/config/userdata.json"
if File.exists? user_data_file then
	begin
		JSON.parse(File.read(user_data_file)).each do |k, v|
			configuration[k] = v
		end
	rescue 
		puts "Could not parse #{user_data_file}"
	end
end
MovieMasher.configure configuration
