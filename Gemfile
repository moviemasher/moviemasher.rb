source 'https://rubygems.org'
source 'http://gems.github.com'

gem 'builder',  		'= 3.1.4'
gem 'mime-types', 		'~> 2.3'
gem 'require_all', 		'= 1.3.2'
gem "multipart-post", 	"= 2.0.0"

group :production do
	gem 'aws-sdk',			'= 1.35.0'
	gem 'uuid', 			'= 2.3.1'
	gem 'json', 			'~> 1.4'
#	gem "rake", 			"= 10.3.2"
end

group :test do
	# for spec tests in /spec
	gem 'clientside_aws', :git => 'https://github.com/perrystreetsoftware/clientside_aws.git'
	gem "rack-test", 		"= 0.5.7"
	gem 'rspec', 			'= 2.14.1'
	gem "hiredis", 		"0.4.5"
	gem "rmagick", :github => "gemhome/rmagick"
end
