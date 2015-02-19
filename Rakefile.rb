task :environment

PathUser = "#{File.dirname(__FILE__)}/../config/userdata.json"
PathConfig = "#{File.dirname(__FILE__)}/../config/config.yml"

namespace :moviemasher do
	desc "If json user data supplied then write it to config, otherwise start web server"
	task :init do 
		require 'json'
		puts "#{Time.now} moviemasher:init called, checking for user data"
		cmd = '/opt/aws/bin/ec2-metadata --user-data'
		puts cmd
		stdin, stdout, stderr = Open3.capture3 cmd
		puts stdin
		no_user_data = stdin.start_with?('user-data: not available')
		if no_user_data then
			puts "#{Time.now} instance was started without user data, starting web server"
			cmd = '/sbin/service httpd restart'
			puts cmd
			result = Open3.capture3 cmd
			puts result
		else
			stdin['user-data: '] = ''
			begin
				parsed = JSON.parse stdin
				user_data_file = PathUser
				File.open(user_data_file, 'w') { |f| f.write(stdin) }
				puts "#{Time.now} saved JSON user data to #{user_data_file}"
			rescue Exception => e
				puts "#{Time.now} could not parse user data as JSON #{e.message}"
				puts stdin
			end
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
