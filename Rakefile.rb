require './index'

task :environment

namespace :moviemasher do
	desc "Initializes instance based on metadata"
	task :init do 
		cmd = '/opt/aws/bin/ec2-metadata --user-data'
		stdin, stdout, stderr = Open3.capture3 cmd
		no_user_data = stdin.start_with?('user-data: not available')
		if no_user_data then
			cmd = '/sbin/service httpd start'
			stdin, stdout, stderr = Open3.capture3 cmd
		else
			stdin['user-data: '] = ''
			begin
				parsed = JSON.parse stdin
				user_data_file = "#{__dir__}/config/userdata.json"
				File.open(user_data_file, 'w') { |f| f.write(stdin) }
			rescue
				puts "could not parse user-data as JSON"
				puts stdin
			end
		end
	end
	
	desc "Checks SQS and directory queues"
	task :process_queues do | t, args |
		puts "#{Time.now} moviemasher:process_queues running"
		STDOUT.flush
		stop_file = "#{CONFIG['dir_temporary']}/disable_process_queues.txt"
		if not File.exists? stop_file then
			begin
				File.open(stop_file, "w") {}
				MovieMasher.process_queues args
			rescue Exception => e
				puts "#{Time.now} caught #{e.message}"
				raise
			ensure
				puts "#{Time.now} moviemasher:process_queues done"
				File.delete(stop_file) if File.exists?(stop_file)
			end
		else
			puts "#{Time.now} moviemasher:process_queues aborting"
		end


	end
end
