
require 'etc'

module MovieMasher
  # initializes azure service
  class AzureInitService < InitService
    def init
      me = 'AzureInitService#init'
      group = 'www-data'
      puts "#{Time.now} #{me} determining hostname and user..."
      user = Etc.getlogin
      cmd = 'hostname'
      stdin = Open3.capture3(cmd).first
      hostname = stdin.strip
      puts "#{cmd}\n#{stdin}"
      puts "#{Time.now} #{me} determining if #{user} user is in #{group} group"
      cmd = 'groups'
      stdin = Open3.capture3(cmd).first
      groups = stdin.strip
      puts "#{cmd}\n#{stdin}"
      unless groups.include?(group)
        puts "#{Time.now} #{me} adding #{user} user to #{group} group"
        cmd = "sudo usermod -a -G #{group} #{user}"
        stdin = Open3.capture3(cmd).first
        puts "#{cmd}\n#{stdin}"
      end
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
          puts "#{Time.now} #{me} angular-moviemasher password now hostname..."
          IO.write('/var/www/config/moviemasher.ini', new_lines.join("\n"))
        end
      end
      false # so we don't overwrite user data
    end
  end
end
