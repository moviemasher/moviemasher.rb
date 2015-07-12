module MovieMasher
  class AwsInitService < InitService
    def init
      result = nil
      puts "#{Time.now} AwsInitService#init called, checking for user data"
      cmd = '/opt/aws/bin/ec2-metadata --user-data'
      puts cmd
      stdin, stdout, stderr = Open3.capture3 cmd
      launch_apache = no_user_data = stdin.start_with?('user-data: not available')
      unless no_user_data
        stdin['user-data: '] = ''
        begin
          result = JSON.parse(stdin)
          unless result['angular-moviemasher'].nil? || !result['angular-moviemasher'].is_a?(Hash)
            puts "#{Time.now} AwsInitService#init found angular-moviemasher config"
            lines = []
            File.foreach(PathIni) do |line|
              line.strip!
              if line.include?('=')
                bits = line.split('=')
                variable = bits.shift
                value = bits.join('=')
                new_value = result['angular-moviemasher'][variable]
                line = "#{variable}=#{new_value}" unless new_value.nil?
              end
              lines << line
            end
            File.open(PathIni, 'w') { |file| file.write(lines.join("\n")) }
            puts "#{Time.now} AwsInitService#init updated angular-moviemasher ini file"
            result.delete('angular-moviemasher')
            launch_apache = true
          end
          result = result['moviemasher.rb'] unless result['moviemasher.rb'].nil?
        rescue Exception => e
          puts "#{Time.now} AwsInitService#init could not parse user data as JSON #{e.message} #{e.backtrace}"
        end
      end
      if launch_apache
        puts "#{Time.now} AwsInitService#init starting web server"
        cmd = '/sbin/service httpd restart'
        puts cmd
        apache_result = Open3.capture3 cmd
        puts apache_result
      end
      result
    end
  end
end
