[![Image](https://rawgit.com/moviemasher/moviemasher.rb/master/README/logo-120x60.png "MovieMasher.com")](https://www.moviemasher.com) **[moviemasher.js](https://github.com/moviemasher/moviemasher.js "stands below angular-moviemasher, providing audiovisual playback handling and edit support in a web browser") | [angular-moviemasher](https://github.com/moviemasher/angular-moviemasher "sits between moviemasher.js and moviemasher.rb, providing an editing GUI and simple CMS middleware layer") | moviemasher.rb**

*Ruby library for mashing up video, images and audio utilizing FFmpeg and Ecasound*
# moviemasher.rb

Use moviemasher.rb to encode mashups of video, audio, and images together with titles and other visual effects.

- **join** files together sequentially with trimming, cropping, and transitions
- **mix** audio tracks together with variable fading and looping
- **composite** visual tracks together with transformations and chromakey
- **add** titling with your own fonts overtop other elements translucently
- **transfer** media files to and from remote hosts using authentication
- **specify** callbacks that alert your system of processing milestones

### Overview
The project aims to simplify common audio/video editing operations by turning your job into a series of shell commands, and then overseeing their execution. As part of job processing, media inputs can be downloaded from remote hosts and rendered outputs can be uploaded as well. Using the same request mechanisms, external systems can be alerted by *callbacks* triggered when a job is started, during its processing and/or when it's completed.

- **Documentation:** generated with RDoc from source [(HTML)](https://rawgit.com/moviemasher/moviemasher.rb/master/doc/index.html)
- **Docker Image:** `moviemasher/moviemasher.rb` [(Dockerfile)](Dockerfile)

In addition to the raw media assets (video, audio and images), jobs can contain *mash* inputs that describe more complex compositing, titling and other effects. The related [**moviemasher.js**](https://github.com/moviemasher/moviemasher.js) project can be used to generate and display JSON formatted mash descriptions within a web browser, and [**angular-moviemasher**](https://github.com/moviemasher/angular-moviemasher) can be used to package these into job descriptions.

Jobs are provided to the system for processing in different ways, depending on how it's been configured and deployed. At the lowest level, the [MovieMasher.process](https://rawgit.com/moviemasher/moviemasher.rb/master/doc/MovieMasher.html#method-c-process) method is sent a job as a hash, a JSON/YAML formatted string or a local path to one. The [MovieMasher.process_queues](https://rawgit.com/moviemasher/moviemasher.rb/master/doc/MovieMasher.html#method-c-process_queues) method calls it with any jobs it finds while scanning a preconfigured watch folder or queue. This scanning can be done for a certain number of seconds, until no jobs are found, just once or forever. There are rake tasks for each of these methods, to simplify calling from shell scripts, cron jobs and other tasks.

### Job Syntax
Each transcoding `job` specifies multiple media `inputs` to be encoded together into one or more `outputs`, as well as metadata like `destination` which defines where to put the final rendered file(s).
##### Scale down local image
```json
{
  "inputs": [{ "source": "/path/to/local.png", "type": "image" }],
  "outputs": [{ "type": "image", "name": "smaller.png", "dimensions": "1536x864" }],
  "destination": { "type": "file", "path": "/path/to", "method": "move" }
}
```

### AWS Integration
The system *optionally* supports [Amazon Web Services](http://aws.amazon.com) for media storage and job queueing, through the ruby [aws-sdk](https://github.com/aws/aws-sdk-ruby) gem. The following mechanisms are available through configuration or job options:

- An [S3](http://aws.amazon.com/s3/) bucket can be a source for inputs or a destination for outputs
- An [SQS](http://aws.amazon.com/sqs/) queue can be polled and messages processed as jobs
- An access key id/secret can be passed to AWS.config for authentication
- Alternatively, environmental variables or an [EC2](http://aws.amazon.com/ec2/) role can authenticate

Additionally, the [Movie Masher AMI](https://aws.amazon.com/marketplace/pp/B00QKW0P2A) is launchable with OneClick in Marketplace as a deployment of all related projects and supporting applications. It includes an upstart task that executes `rake moviemasher:init` to merge any User Data supplied in JSON format into the configuration plus a cron job that continually executes `rake moviemasher:process_queues`, so it's possible to run in a headless mode polling an SQS queue for jobs. Without User Data, the instance will start up Apache and serve the angular-moviemasher project for demonstration - the instance id acts as a shared password.

### Docker Usage
Docker's  [`moviemasher/moviemasher.rb`](https://registry.hub.docker.com/u/moviemasher/moviemasher.rb/) image is based off the official [`ruby`](https://registry.hub.docker.com/_/ruby/) image, adding builds of [FFmpeg](http://www.ffmpeg.org), [Ecasound](http://eca.cx/ecasound/) and supporting audio/visual libraries. It can be used to process jobs supplied directly on the command line, or to grab them from a directory/queue - either approach supports running in interractive or daemon mode. The Dockerfile contains a **VOLUME** instruction for each directory it works with, including **queue_directory** so that job files residing on the host can be easily processed.

- To display documentation of configuration options:

    `docker run -it --rm moviemasher/moviemasher.rb moviemasher --help`

- To process jobs directly from the command line:

	`docker run -it --rm moviemasher/moviemasher.rb process "JOB" "JOB"`

  JOB can be a JSON or YAML formatted string, or a path to one in the container.

- To process all JSON or YAML formatted jobs in directory 'my_jobs' residing on the host:

	`docker run -it --rm -v my_jobs:/tmp/moviemasher/queue moviemasher/moviemasher.rb`

- To continually process jobs from container's queue volume:

  	`docker run -d -t --name=moviemasher moviemasher/moviemasher.rb process_loop`

  Note the `t` switch - it's required for Ecasound to function properly. You'll need to subsequently execute `docker stop moviemasher` and `docker rm moviemasher` to stop processing and remove the container created.

- To process a single job from an SQS queue:

	`docker run -it --rm moviemasher/moviemasher.rb process_one --queue_url=[URL] --aws_access_key_id=[ID] --aws_secret_access_key=[SECRET]`

  URL points to an existing SQS Queue that provides read/write access to the owner of the access key with ID and SECRET. Messages can be in JSON or YAML format.

The last example demonstrates overriding the configuration with command line arguments - all commands support this. The **MOVIEMASHER_CONFIG** environmental variable can also be set to a configuration file residing on the container in JSON/YAML format, though arguments take precedence.

When processing jobs in a directory or queue, the **process_seconds** configuration option ultimately controls how long polling continues and therefore how long the container runs. The following values are supported:

- [N]: poll for N seconds, then exit
- 0: do not poll, just exit
- -1: process a single job if found, then exit
- -2: poll until no jobs remain, then exit
- -3: poll until container stopped

The Dockerfile specifies an **ENTRYPOINT** that provides several convenience commands, but calls exec with any it doesn't recognize so that containers behave as expected. The following commands are supported:

- moviemasher (default): call [MovieMasher.process_queues](https://rawgit.com/moviemasher/moviemasher.rb/master/doc/MovieMasher.html#method-c-process_queues)
- process_one:  call [MovieMasher.process_queues](https://rawgit.com/moviemasher/moviemasher.rb/master/doc/MovieMasher.html#method-c-process_queues) with **process_seconds**=-1
- process_all:  call [MovieMasher.process_queues](https://rawgit.com/moviemasher/moviemasher.rb/master/doc/MovieMasher.html#method-c-process_queues) with **process_seconds**=-2
- process_loop:  call [MovieMasher.process_queues](https://rawgit.com/moviemasher/moviemasher.rb/master/doc/MovieMasher.html#method-c-process_queues) with **process_seconds**=-3
- process: call [MovieMasher.process](https://rawgit.com/moviemasher/moviemasher.rb/master/doc/MovieMasher.html#method-c-process) for each supplied argument

### Requirements
Tested in Ruby 1.9.3 and 2.1.5 (the `dockerfile/ruby` and `ruby` docker images) and on multiple UNIX flavors including OSX. Suggested audio/video libraries are only needed if you're decoding or encoding in their formats. Likewise, the aws-sdk gem is only needed when utilizing Amazon's services.

- Applications: [FFmpeg](http://www.ffmpeg.org), [Ecasound](http://eca.cx/ecasound/), [Sox](http://sox.sourceforge.net)
- Ruby Gems: aws-sdk, builder, mime-types, multipart-post, require_all,  uuid
- Audio Libraries: mp3lame, ogg, opencore, samplerate, sndfile, speex, theora, vorbis
- Video Libraries: dirac, fontconfig, frei0r, fribidi, gd, openjpeg, vpx, xvidcore, x264


### How to Install
Transcoding audio and video is extremely processor intensive, so while installation might be possible on most machines it isn't reccommended for all environments. In particular, running alongside a web server is only practical for demonstration purposes. Typically in production a pool of machines is deployed with each instance running a single process solely engaged in transcoding.

1. Review [Dockerfile](Dockerfile) for commands that work on the `ruby` image
1. Install av libraries for supported formats and codecs
1. Install sox, ecasound and ffmpeg applications (in that order)
1. Install ruby and bundler gem
1. To install required gems `cd` to project directory and execute:

   `bundle install`

6. Edit config/config.yml configuration file to match paths on system and configure logging/debugging options

7. To scan watch folder and/or queue for jobs `cd` to project directory and execute:

   `rake moviemasher:process_queues`

8. *optionally* add crontab entry from config/aws/moviemasher.cron, after checking its binary paths


### User Feedback
If any problems arise while utilizing this repository, a [GitHub Issue Ticket](https://github.com/moviemasher/moviemasher.rb/issues) should be filed. Please include the job description that's causing problems and any relevant log entries - issues with callbacks can typically be resolved faster after seeing entries from the receiving web server's log. Please post your issue ticket in the appropriate repository and refrain from cross posting - all projects are monitored with equal zeal.


### Contributing
Please join in the shareable economy by gifting your efforts towards improving this project in any way you feel inclined. Pull requests for fixes, features and refactorings are always appreciated, as are documentation updates. Creative help with graphics, video and the web site is also needed. Please contact through [MovieMasher.com](https://moviemasher.com) to discuss your ideas.

#### Developer Setup
Docker is used extensively to develop this project. Additionally, the spec tests rely on the other two Movie Masher projects which should both be cloned into the same directory that contains this repository:

- [moviemasher.js](https://github.com/moviemasher/moviemasher.js)
- [angular-moviemasher](https://github.com/moviemasher/angular-moviemasher)


To run spec tests utilizing options from `.rspec` file:

- `docker-compose -f config/docker/rspec/docker-compose.yml run --rm rspec`

All files generated by tests appear in `tmp/spec` sub directories. Each job has its own log file in `tmp/spec/temporary`.

To run rubocop with options from
`config/docker/rubocop/rubocop-rules.yml`
file:

- `docker-compose -f config/docker/rubocop/docker-compose.yml run --rm rubocop`

To rebuild Gemfile.lock from Gemfile:
- `docker-compose -f config/docker/bundler/docker-compose.yml run --rm bundler`

To have rdoc rebuild documentation in `doc` from source code:

- `rdoc --visibility=public -o doc --main='Documentation.md' --fmt=darkfish --markup=tomdoc --tab-width=2 --no-dcov --exclude='/spec' --exclude='/log' --exclude='/Gemfile' --exclude='/tmp' --exclude='/config' --exclude='/index.rb' --exclude='/doc' --exclude='/bin' --exclude='/Rakefile' --exclude='/Docker' --exclude='/README-short' --exclude='/LICENSE'`


##### Known issues in this version
- archiving of outputs not yet supported (coming soon)
- freeze frame not yet supported
- audio still being done in Ecasound
- audio spec tests not yet generating files from scratch

##### Migrating from Version 4.0.7
- The `length` key in clips has been renamed `frames`.
- The `audio` and `video` keys in mash tracks have been moved to mash.
- The `tracks` key in mashes has been removed.
- The `fps` key in outputs has been renamed `video_rate`.
- The `audio_frequency` key in outputs has been renamed `audio_rate`.
- The `trim` key in inputs has been renamed `offset`.
- The new `mash` key in mash inputs should be used for embedded mashes
- The `source` key in mash inputs should only contain a source object
