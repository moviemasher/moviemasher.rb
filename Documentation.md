![Image](https://github.com/moviemasher/moviemasher.rb/raw/master/README/logo-120x60.png "MovieMasher.com") **[moviemasher.js](https://github.com/moviemasher/moviemasher.js "stands below angular-moviemasher, providing audiovisual playback handling and edit support in a web browser") | [angular-moviemasher](https://github.com/moviemasher/angular-moviemasher "sits between moviemasher.js and moviemasher.rb, providing an editing GUI and simple CMS middleware layer") | [moviemasher.rb](https://github.com/moviemasher/moviemasher.rb "sits behind angular-moviemasher, providing processor intensive video transcoding services through a simple API")**

*Ruby library for mashing up video, images and audio utilizing FFmpeg and Ecasound* 
# moviemasher.rb

---

### RDoc Documentation


##### Core Classes/Modules


- MovieMasher
- MovieMasher::Job
- MovieMasher::Input
- MovieMasher::Output
- MovieMasher::Transfer
  - MovieMasher::Source
  - MovieMasher::Destination
  - MovieMasher::Callback



##### Core Usage


	require_relative 'lib/moviemasher.rb'
	job = { :inputs => [], :base_source => {}, :outputs => [], :destination => {} }
	job[:base_source][:path] = job[:destination][:path] = '~/'
	job[:inputs] << { :type => 'video', :source => 'input.mov', :fill => 'crop' }
	job[:inputs] << { :type => 'image', :source => 'input.jpg', :length => 2 }
	job[:inputs] << { :type => 'audio', :source => 'input.mp3', :offset => 10 }
	job[:outputs] << { :type => 'video', :name => 'output.mp4' }
	MovieMasher.process job

When inputs use relative URLs like the example above then either the input or the job needs a `base_source` key containing a MovieMasher::Transfer object to resolve them to absolute ones. Likewise, a `destination` key containing a MovieMasher::Destination object can be placed either in an output or the job for all outputs to use to resolve relative locations. We've set them both to our home directory in this case so all files live there. 

Inputs are arranged consecutively one after the other - at least the visual ones. Audio inputs will by default start where the last audio or video with audio ends, so if the video input in our example has audio the audio input will start after it, otherwise they will begin at the same time. You can also explicitly play an audio track at any time by specify its `start` value. 

In addition to raw media (video, audio and images) it's also possible to output image sequences from video tracks and waveform graphics from audio tracks. In terms of inputs, it's also possible to provide a mash JSON payload like moviemasher.js creates. Within a mash input, visual elements can be composited together just like audio elements can in the job itself. 

The visual composition of inputs is controlled by *effect, scaler* and *merger* media, which are all arrangements of FFmpeg *filters*. Only a subset of filters and their parameters are supported at this time, but they include basics like crop, scale, fade and drawtext. That last one relies on *font* media, the last of the modular types. 


**To regenerate this documentation `cd` to project directory and execute:**
    
    rdoc --visibility=public -o doc --main='Documentation.md' --fmt=darkfish --markup=tomdoc --tab-width=2 --no-dcov --exclude='/spec' --exclude='/log' --exclude='/Gemfile' --exclude='/tmp' --exclude='/config' --exclude='/index.rb' --exclude='/doc' --exclude='/bin' --exclude='/Rakefile' --exclude='/Docker' --exclude='/README-short' --exclude='/LICENSE' 
