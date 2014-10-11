[![Image](https://www.moviemasher.com/media/remote/logo-120x60.png "MovieMasher.com")](http://moviemasher.com)
** [moviemasher.js](https://github.com/moviemasher/moviemasher.js "stands below angular-moviemasher, providing audiovisual playback handling and edit support in a web browser") | [angular-moviemasher](https://github.com/moviemasher/angular-moviemasher "sits between moviemasher.js and moviemasher.rb, providing an editing GUI and simple CMS middleware layer") | moviemasher.rb **
#moviemasher.rb
*Ruby library for mashing video, audio and images with filters in FFmpeg* 

---
Use the API in moviemasher.rb to encode mashups of video, audio, and images in FFmpeg and Ecasound. It provides a simplified syntax for describing complex compositing, transforming and mixing operations.  

### Usage

require 'moviemasher.rb'


### Requirements
- ffmpeg
- ecasound
- sox
- builder gem
- require_all gem
- json gem
- uuid gem
- mime-types gem
- multipart-post gem
- rake gem
- rack gem
- aws-sdk gem

### Developer Steps
1. install ruby and builder
2. uncomment entries in Gemfile 
3. bundle install

##### To run tests in spec_aws
1. install and launch clientside_aws 
2. uncomment entries in Gemfile 
3. bundle install
