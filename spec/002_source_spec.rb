require_relative 'helpers/spec_helper'

describe File.basename(__FILE__) do
  context 'Source#full_path' do
    it 'correctly deals with leading and trailing slashes' do
      source = MovieMasher::Source.new(directory: 'DIR/', path: '/PATH.ext')
      expect(source.full_path).to eq 'DIR/PATH.ext'
    end
  end
  context 'Source#url' do
    it 'correctly returns url if defined' do
      source = MovieMasher::Source.new(url: 'URL')
      expect(source.url).to eq source[:url]
    end
    it 'correctly returns file url for file source with just path' do
      path = 'PATH/To/file.jpg'
      source = MovieMasher::Source.new(type: 'file', path: path)
      expect(source.url).to eq path
    end
    it 'correctly returns file url for source with path, name and extension' do
      path = 'PATH'
      name = 'NAME'
      extension = 'EXTENSION'
      hash = { type: 'file', path: path, name: name, extension: extension }
      source = MovieMasher::Source.new(hash)
      file_name = "#{name}.#{extension}"
      expect(source.url).to eq MovieMasher::Path.concat(path, file_name)
    end
  end
  context 'Input#url' do
    it 'correctly returns url when source is simple url' do
      url = 'http://www.example.com:1234/path/to/file.jpg'
      input = MovieMasher::Input.new(type: 'image', url: url)
      input.preflight
      expect(input.url).to eq url
    end
    it 'correctly returns file url when source is file object' do
      hash = {
        type: 'image', source: {
          type: 'file', path: '/path/to', name: 'file', extension: 'jpg'
        }
      }
      input = MovieMasher::Input.new(hash)
      input.preflight
      url = input.url
      source = input.source
      file_name = "#{source[:name]}.#{source[:extension]}"
      expect(url).to eq MovieMasher::Path.concat(source[:path], file_name)
    end
  end
end
