
require_relative 'helpers/spec_helper'

describe File.basename(__FILE__) do
	context "__path_for_transfer" do
		it "correctly deals with leading and trailing slashes" do
			source = {:directory => 'DIR/', :path => '/PATH.ext'}
			expect(MovieMasher::Job.send :__path_for_transfer, source).to eq 'DIR/PATH.ext'
		end
	end
	context "__url_for_source" do
		it "correctly returns url if defined" do
			source = {:url => 'URL'}
			expect(MovieMasher::Job.send :__url_for_source, source).to eq source[:url]
		end
		it "correctly returns file url for file source with just path" do
			source = {:type => 'file', :path => 'PATH'}
			expect(MovieMasher::Job.send :__url_for_source, source).to eq "#{source[:type]}:///#{source[:path]}"
		end
		it "correctly returns file url for file source with path, name and extension" do
			source = {:type => 'file', :path => 'PATH', :name => 'NAME', :extension => 'EXTENSION'}
			expect(MovieMasher::Job.send :__url_for_source, source).to eq MovieMasher::Path.concat "#{source[:type]}:///#{source[:path]}", "#{source[:name]}.#{source[:extension]}"
		end
	end
	context "__url_for_input" do
		it "correctly returns url when source is simple url" do
			input = { :type =>"image", :url => "http://www.example.com:1234/path/to/file.jpg" }
			input = MovieMasher::Job.send :__init_input, input
			url = MovieMasher::Job.send :__url_for_input, input
			expect(url).to eq input[:url]
		end
		it "correctly returns file url when source is file object" do
			input = { :type => "image", :source => { :type => "file", :path => "/path/to", :name => "file", :extension => "jpg" } }
			url = MovieMasher::Job.send :__url_for_input, input
			source = input[:source]
			expect(url).to eq MovieMasher::Path.concat "#{source[:type]}://#{source[:path]}", "#{source[:name]}.#{source[:extension]}"
		end
	end
end