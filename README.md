[![Image](https://www.moviemasher.com/media/remote/logo-120x60.png "MovieMasher.com")](http://moviemasher.com)
**[moviemasher.js](https://github.com/moviemasher/moviemasher.js "stands below angular-moviemasher, providing audiovisual playback handling and edit support in a web browser") | [angular-moviemasher](https://github.com/moviemasher/angular-moviemasher "sits between moviemasher.js and moviemasher.rb, providing an editing GUI and simple CMS middleware layer") | moviemasher.rb**
#moviemasher.rb
*Ruby library for mashing up video, images and audio utilizing FFmpeg and Ecasound* 

---
Use moviemasher.rb to encode mashups of video, audio, and images in FFmpeg and Ecasound from a JSON formatted job description.
A job specifies multiple media inputs to be encoded together into one or more outputs, as well as where to find the inputs and where to place the outputs. 

 
- **concatenate** files together sequentially with trimming
- **mix** audio tracks together with variable fading
- **composite** visual tracks together with transformations
- **add** titling as an effect or theme with custom fonts
- **transfer** encoded files to a web host or to S3 with aws-sdk
 
The project includes a rake task that can be routinelly called to watch a folder for job description files, or to poll an SQS queue as well. There are also configuration files for supporting applications like cron, logrotate and upstart, though these are optimized for AWS LINUX deployment and probably need tweaking for your system.

 Media inputs can reside on the local drive, a remote web host or in Amazon's S3 service. Likewise, encoded outputs can be placed on the local drive, a remote web host or in S3. Remote transfers can be authenticated, and if the local host is an EC2 instance then its role can be used for S3 transfers (or any mechanism supported by aws-sdk).


### Basic Usage

	require_relative 'lib/moviemasher.rb'
	job = { :inputs => [], :base_source => {}, :outputs => [], :destination => {} }
	job[:base_source][:path] = job[:destination][:path] = '~/'
	job[:inputs] << { :type => 'video', :source => 'input.mov', :trim => 5 }
	job[:inputs] << { :type => 'image', :source => 'input.jpg', :length => 2 }
	job[:inputs] << { :type => 'audio', :source => 'input.mp3', :gain => 1.5 }
	job[:outputs] << { :type => 'video', :name => 'output.mp4' }
	MovieMasher.process job

When inputs use relative URLs like the example above then either the input or the job needs a `base_source` object to resolve them to absolute URLs. Likewise, a `destination` object resolves the location of outputs and can be placed either in them or in the job. We've set them both to our home directory in this case so all files live there. 

Inputs are arranged consecutively one after the other, at least the visual ones. Audio inputs will by default start where the last audio or video with audio ends, so if the video input in our example has audio the audio input will start after it, otherwise they will begin at the same time. You can also explicitly play an audio track at any time by specify its `start` value. 

In addition to raw media (video, audio and images) it's also possible to output image sequences from video tracks and waveform graphics from audio tracks. In terms of inputs, it's also possible to provide a mash JSON payload like moviemasher.js creates. Within a mash input, visual elements can be composited together just like audio elements can in the job itself. 

The visual composition of inputs is controlled by *effect, scaler* and *merger* media, which are all arrangements of FFmpeg *filters*. Only a subset of filters and thier parameters are supported at this time, but they include basics like crop, scale, fade and drawtext. That last one relies on *font* inputs, the last of the custom input types. 

### Related Projects
Three separate projects - *moviemasher.js, angular-moviemasher and moviemasher.rb* - can be combined to engineer a complete, browser-based audio/video editing and encoding system. Or projects can be utilized independently, if editing or encoding features are all that's needed. Only angular-moviemasher is dependent on the other projects, since it's designed to sit between them as a middleware layer providing content managemnt functions.

### Requirements
- ffmpeg
- ecasound
- sox
- du
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

##### Known issues in Version 4.0.07
- little documentation - see angular-moviemasher's PHP for usage
- local/sqs import/export has not been thoroughly tested
- support needed for archiving of outputs
- support needed for freeze frame

