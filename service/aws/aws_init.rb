# frozen_string_literal: true

module MovieMasher
  # initializes aws service
  class AwsInitService < InitService
    def init
      me = 'AwsInitService#init'
      result = nil
      puts "#{Time.now} #{me} called, checking for user data"
      cmd = '/opt/aws/bin/ec2-metadata --user-data'
      puts cmd
      stdin = Open3.capture3(cmd).first
      launch_apache = no_data = stdin.start_with?('user-data: not available')
      unless no_data
        stdin['user-data: '] = ''
        begin
          result = JSON.parse(stdin)
          if result['angular-moviemasher'].is_a?(Hash)
            puts "#{Time.now} #{me} found angular-moviemasher config"
            lines = __lines_in_ini(result)
            File.open(PathIni, 'w') { |file| file.write(lines.join("\n")) }
            puts "#{Time.now} #{me} updated angular-moviemasher ini file"
            result.delete('angular-moviemasher')
            launch_apache = true
          end
          result = result['moviemasher.rb'] unless result['moviemasher.rb'].nil?
        rescue StandardError => e
          puts "#{Time.now} #{me} couldn't parse user data as JSON #{e.message}"
        end
      end
      if launch_apache
        puts "#{Time.now} #{me} starting web server"
        cmd = 'systemctl restart httpd'
        puts cmd
        apache_result = Open3.capture3 cmd
        puts apache_result
      end
      result
    end

    def __lines_in_ini(result)
      lines = []
      File.foreach(PathIni) do |line|
        line.strip!
        if line.include?('=')
          bits = line.split('=')
          variable = bits.shift
          new_value = result['angular-moviemasher'][variable]
          line = "#{variable}=#{new_value}" unless new_value.nil?
        end
        lines << line
      end
      lines
    end
  end
end
