task :environment

PathUser = "#{File.dirname(__FILE__)}/../config/userdata.json"
PathConfig = "#{File.dirname(__FILE__)}/../config/config.yml"
PathIni = "#{File.dirname(__FILE__)}/../config/moviemasher.ini"

namespace :moviemasher do
	desc "Instances service and calls its init method, saving result to #{PathUser}"
	task :init, :service_id, :config_path, :user_config_path do | t, args |
		service_id = args[:service_id]
		if service_id.nil? or service_id.empty?
			puts "#{Time.now} moviemasher:init aborted because no service id parameter provided"
		else
			require_relative 'lib/moviemasher'
      MovieMasher.configure args[:config_path] || PathConfig
      MovieMasher.configure args[:user_config_path] || PathUser
			init_service = MovieMasher::Service.initer service_id
			if init_service
        puts "#{Time.now} moviemasher:init '#{service_id}' starting..."
				parsed = init_service.init
				if parsed
					File.open(PathUser, 'w') { |f| f.write(parsed.to_json) }
					puts "#{Time.now} saved JSON user data to #{PathUser}"
				end
			end
      puts "#{Time.now} moviemasher:init '#{service_id}' completed"
		end
	end
	desc "Checks SQS and directory queues"
	task :process_queues, :config_path, :user_config_path do | t, args |
		require_relative 'lib/moviemasher'
		MovieMasher.configure args[:config_path] || PathConfig
		MovieMasher.configure args[:user_config_path] || PathUser
		puts "#{Time.now} moviemasher:process_queues called"
		STDOUT.flush
		stop_file = MovieMasher::Path.concat(MovieMasher.configuration[:render_directory], 'disable_process_queues.txt')
		if not File.exists? stop_file then
			begin
				File.open(stop_file, "w") {}
				MovieMasher.process_queues
			rescue Exception => e
				puts "#{Time.now} moviemasher:process_queues caught #{e.message}"
				raise
			ensure
				puts "#{Time.now} moviemasher:process_queues completed"
				File.delete(stop_file) if File.exists?(stop_file)
			end
		else
			puts "#{Time.now} moviemasher:process_queues aborted because stop file found #{stop_file}"
		end
	end
end
