require 'etc'
module MovieMasher
	class AzureInitService < InitService
		def init
      group = 'www-data'
      puts "#{Time.now} AzureInitService#init determining hostname and user..."
      user = Etc.getlogin	  
      cmd = 'hostname'
      stdin, stdout, stderr = Open3.capture3 cmd
      hostname = stdin.strip
      puts "#{cmd}\n#{stdin}"
      
      unless hostname.empty?
        lines = IO.readlines('/var/www/config/moviemasher.ini')
        auth_key = 'authentication='
        new_lines = []
        found = false
        added = false
        auth_value = "#{auth_key}#{hostname}"
        lines.each do |line|
          line.strip!
          if line.start_with?(auth_key)
            found = true
            line[auth_key] = ''
            if line.strip.empty?
              new_lines << auth_value
              added = true
            else
              new_lines << line
            end
          else
            new_lines << line
          end
        end
        unless found
         new_lines << auth_value 
          added = true
        end
        if added
          puts "#{Time.now} AzureInitService#init setting angular-moviemasher password to hostname..." 
          IO.write('/var/www/config/moviemasher.ini', new_lines.join("\n"))
        end
      end
      
      
      puts "#{Time.now} AzureInitService#init determining if #{user} user is in #{group} group"
      cmd = 'groups'
      stdin, stdout, stderr = Open3.capture3 cmd
      groups = stdin.strip
      puts "#{cmd}\n#{stdin}"

      unless groups.include?(group)
        puts "#{Time.now} AzureInitService#init adding #{user} user to #{group} group"
        cmd = "sudo usermod -a -G #{group} #{user}"
        stdin, stdout, stderr = Open3.capture3 cmd
        puts "#{cmd}\n#{stdin}"
      end

#      puts "#{Time.now} AzureInitService#init starting apache2..."
#      cmd = 'sudo service apache2 restart'
#      stdin, stdout, stderr = Open3.capture3 cmd
#      puts "#{cmd}\n#{stdin}"

			false # so we don't overwrite user data
		end
	end
end
