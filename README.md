[![Image](https://github.com/moviemasher/moviemasher.rb/blob/master/README/logo-120x60.png "MovieMasher.com")](http://moviemasher.com)
**[moviemasher.js](https://github.com/moviemasher/moviemasher.js "stands below angular-moviemasher, providing audiovisual playback handling and edit support in a web browser") | [angular-moviemasher](https://github.com/moviemasher/angular-moviemasher "sits between moviemasher.js and moviemasher.rb, providing an editing GUI and simple CMS middleware layer") | moviemasher.rb**

*Ruby library for mashing up video, images and audio utilizing FFmpeg and Ecasound* 
#moviemasher.rb

Use moviemasher.rb to encode mashups of video, audio, and images from a JSON formatted job description. A job specifies multiple media inputs to be encoded together into one or more outputs, as well as where to find the inputs and where to place the outputs. 

- **concatenate** files together sequentially with trimming
- **mix** audio tracks together with variable fading
- **composite** visual tracks together with transformations
- **add** titling as an effect or theme with custom fonts
- **transfer** encoded files to remote hosts
- **specify** callbacks that alert your system of processing milestones

The project aims to take the complexity out of describing common audio/video editing operations to command line programs, which handle the low level transcoding operations. The MovieMasher class turns your job into a series of commands and then manages their execution. 

As part of job processing it can download media inputs from remote hosts and upload media outputs as well. Using the same mechanisms it can also trigger callbacks as a job is started, during its processing and when it's completed so that external systems can be alerted.

The project includes a rake task that can be routinely called to watch a folder for job description files, as well as an example crontab entry that calls it. Recall that ruby scripts run from cron lack your user's environmental variables, so you'll probably need to edit the paths to binary directories in the entry to match your system.

### Amazon Web Services Integration
There are optional configuration settings that support two specific AWS offerings: S3 for media storage and SQS for job queueing. If set to use an SQS queue then it will be polled as part of the folder watching process for job files. The ruby aws-sdk is utilized to interface with SQS, so access key details can be provided in the configuration or environmental variables or in a role if deployed on an EC2 instance. 

Similarly, aws-sdk is utilized for S3 interactions so if access key details are present then buckets can be used either as sources for media inputs or destinations for media outputs within job descriptions. These are authenticated requests, so the buckets do not have to be public.

Additionally, the Movie Masher AMI is available in Marketplace and includes moviemasher.rb and all supporting applications. When launched it looks for  user data supplied in JSON format and merges it into the default configuration, so it's possible to supply SQS options on startup. The cron job described above is installed, so a configured SQS queue will immediately start being polled for jobs. Otherwise the instance will start up apache to serve the angular-moviemasher project, preconfigured to utilize the local moviemasher.rb process (the instance id acts as a shared password).

### Basic Ruby Usage

	require_relative 'lib/moviemasher.rb'
	job = { :inputs => [], :base_source => {}, :outputs => [], :destination => {} }
	job[:base_source][:path] = job[:destination][:path] = '~/'
	job[:inputs] << { :type => 'video', :source => 'input.mov', :fill => 'crop' }
	job[:inputs] << { :type => 'image', :source => 'input.jpg', :length => 2 }
	job[:inputs] << { :type => 'audio', :source => 'input.mp3', :trim => 10 }
	job[:outputs] << { :type => 'video', :name => 'output.mp4' }
	MovieMasher.process job

When inputs use relative URLs like the example above then either the input or the job needs a `base_source` object to resolve them to absolute ones. Likewise, a `destination` object resolves the location of outputs and can be placed either in them or in the job in order to be available to all outputs. We've set them both to our home directory in this case so all files live there. 

Inputs are arranged consecutively one after the other - at least the visual ones. Audio inputs will by default start where the last audio or video with audio ends, so if the video input in our example has audio the audio input will start after it, otherwise they will begin at the same time. You can also explicitly play an audio track at any time by specify its `start` value. 

In addition to raw media (video, audio and images) it's also possible to output image sequences from video tracks and waveform graphics from audio tracks. In terms of inputs, it's also possible to provide a mash JSON payload like moviemasher.js creates. Within a mash input, visual elements can be composited together just like audio elements can in the job itself. 

The visual composition of inputs is controlled by *effect, scaler* and *merger* media, which are all arrangements of FFmpeg *filters*. Only a subset of filters and their parameters are supported at this time, but they include basics like crop, scale, fade and drawtext. That last one relies on *font* media, the last of the modular types. 

### How to Install and Use
1. install ffmpeg, ecasound, sox and du programs
2. install ruby and builder
3. `bundle install` in project directory installs required gems from Gemfile
4. edit config/config.yml configuration file to match paths on system and configure logging/debugging options
5. `rake moviemasher:process_queues` searches watch folder and optional SQS queue for jobs
6. optionally install calling crontab entry found at config/moviemasher.cron after checking binary paths in it

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
1. uncomment entries in Gemfile related to spec tests
2. `bundle install` from project directory installs additional gems
3. `rspec spec` will run the core tests

##### To run tests in spec_aws
1. install and launch clientside_aws 
2. uncomment other entries in Gemfile 
3. `bundle install` from project directory installs additional gems

##### Known issues in Version 4.0.07
- little documentation - see PHP in angular-moviemasher project for job construction examples
- local/sqs import/export has not been thoroughly tested
- archiving of outputs not yet supported
- freeze frame not yet supported
- audio still being done in Ecasound

