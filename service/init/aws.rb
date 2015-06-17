module MovieMasher
	class AwsInitService < InitService
		def init
			result = nil
			puts "#{Time.now} AwsInitService#init called, checking for user data"
			cmd = '/opt/aws/bin/ec2-metadata --user-data'
			puts cmd
			stdin, stdout, stderr = Open3.capture3 cmd
			puts stdin
			no_user_data = stdin.start_with?('user-data: not available')
			if no_user_data then
				puts "#{Time.now} AwsInitService#init instance was started without user data, starting web server"
				cmd = '/sbin/service httpd restart'
				puts cmd
				apache_result = Open3.capture3 cmd
				puts apache_result
			else
				stdin['user-data: '] = ''
				begin
					result = JSON.parse stdin
				rescue Exception => e
					puts "#{Time.now} AwsInitService#init could not parse user data as JSON #{e.message}"
				end
			end
			result
		end
	end
end
