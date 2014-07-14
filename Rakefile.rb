require './index'

task :environment

namespace :moviemasher do
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
