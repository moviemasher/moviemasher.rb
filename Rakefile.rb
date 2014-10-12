task :environment

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
				user_data_file = "#{__dir__}/config/userdata.json"
				File.open(user_data_file, 'w') { |f| f.write(stdin) }
				puts "#{Time.now} saved JSON user data to #{user_data_file}"
			rescue Exception => e
				puts "#{Time.now} could not parse user data as JSON #{e.message}"
				puts stdin
			end
		end
	end
	desc "Checks SQS and directory queues"
	task :process_queues do
		require './index'
		puts "#{Time.now} moviemasher:process_queues called"
		STDOUT.flush
		stop_file = "#{MovieMasher.configuration[:dir_temporary]}disable_process_queues.txt"
		if not File.exists? stop_file then
			begin
				File.open(stop_file, "w") {}
				MovieMasher.process_queues
			rescue Exception => e
				puts "#{Time.now} moviemasher:process_queues caught #{e.message}"
				raise
			ensure
				puts "#{Time.now} moviemasher:process_queues completed without exception"
				File.delete(stop_file) if File.exists?(stop_file)
			end
		else
			puts "#{Time.now} moviemasher:process_queues aborted because stop file found #{stop_file}"
		end
	end
end
namespace :test do
	desc "Tests S3 put action"
	task :s3, :bucket, :key, :file, :acl, :content_type, :region do | t, args |

		if args[:bucket] and args[:key] and args[:file] and File.exists?(args[:file])
			args[:region] = 'us-east-1' unless args[:region]
			options = Hash.new
			options[:acl] = args[:acl].to_sym if args[:acl]
			options[:content_type] = args[:content_type] if args[:content_type]
			s3 = AWS::S3.new(:region => args[:region])
			bucket = s3.buckets[args[:bucket]]
			s3_object = bucket.objects[args[:key]]
			s3_object.write(Pathname.new(args[:file]), options)
		else
			puts "invalid parameters"
		end
	end
end
