FROM ruby:2.1
MAINTAINER Movie Masher <support@moviemasher.com>

ENV HOME /root

# install tools and helpers
RUN apt-get update && apt-get install -y \
  apt-utils \
  build-essential \
  checkinstall \
  cmake \
  git \
  subversion \
  wget \
  yasm

# install video libs and plugins
RUN apt-get update && apt-get install -y \
  libdirac-dev \
  libfontconfig-dev \
  libfribidi-dev \
  libgd-dev \
  libvpx-dev \
  libxvidcore-dev \
  frei0r-plugins-dev

# install audio libs and apps
RUN apt-get update && apt-get install -y \
  libmp3lame-dev \
  libogg-dev \
  libopencore-amrnb-dev \
  libopencore-amrwb-dev \
  libsamplerate-dev \
  libsndfile-dev \
  libsox-dev \
  libspeex-dev \
  libtheora-dev \
  libvorbis-dev \
  sox \
  ecasound

# clean up apt and temporary directories
RUN apt-get clean; rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# ffmpeg prefers openjpeg 1.5.x, so we compile it from source - 11/15/2014
WORKDIR /data
RUN \
  wget https://downloads.sourceforge.net/project/openjpeg.mirror/1.5.2/openjpeg-1.5.2.tar.gz; \
  tar -xzvf openjpeg-1.5.2.tar.gz; \
  cd /data/openjpeg-1.5.2; \
  cmake .; \
  make; \
  make install; \
  cd /data; \
  rm -R /data/openjpeg-1.5.2

# pull, configure, make and install x264
WORKDIR /data
RUN \
  git clone git://git.videolan.org/x264.git; \
  cd /data/x264; \
  ./configure --prefix=/usr --enable-shared; \
  make; \
  make install; \
  cd /data; \
  rm -R /data/x264

# pull, configure, make and install ffmpeg
WORKDIR /data
RUN \
  git clone git://source.ffmpeg.org/ffmpeg.git ffmpeg; \
  cd /data/ffmpeg; \
  ./configure \
    --enable-frei0r \
    --enable-gpl \
    --enable-libfontconfig \
    --enable-libfreetype \
    --enable-libfribidi \
    --enable-libmp3lame \
    --enable-libopencore-amrnb \
    --enable-libopencore-amrwb \
    --enable-libopenjpeg \
    --enable-libspeex \
    --enable-libtheora \
    --enable-libvorbis \
    --enable-libvpx \
    --enable-libx264 \
    --enable-libxvid \
    --enable-postproc \
    --enable-pthreads \
    --enable-version3 \
    --enable-zlib \
    --extra-cflags="-I/usr/local/include/openjpeg" \
  ; \
  make; \
  make install; \
  cd /data; \
  rm -R /data/ffmpeg

# needed for binaries to find libraries
RUN ldconfig

# install our production gems
COPY Gemfile /data/
COPY Gemfile.lock /data/
WORKDIR /data
RUN \
  bundle config --global frozen 1; \
  bundle install --without test development

# copy, make and install wav2png
COPY bin/wav2png/* /data/wav2png/
WORKDIR /data/wav2png
RUN \
  make; \
  mv wav2png /usr/bin/; \
  cd /data; \
  rm -R /data/wav2png

# copy everything except what's caught by .dockerignore
COPY . /mnt/moviemasher.rb/
WORKDIR /mnt/moviemasher.rb

# install our entry point, with default command
CMD ["moviemasher"]
ENTRYPOINT ["config/docker/entrypoint.rb"]

# expose all our configurable directories as potential mount points
VOLUME /tmp/moviemasher/queue
VOLUME /tmp/moviemasher/log
VOLUME /tmp/moviemasher/render
VOLUME /tmp/moviemasher/download
VOLUME /tmp/moviemasher/error

# EVERYTHING BELOW CAN BE UNCOMMENTED TO PRODUCE DEV IMAGE

## # install redis for aws-sdk
## RUN \
##   cd /data; \
##   wget "http://download.redis.io/releases/redis-2.8.17.tar.gz"; \
##   gunzip redis-2.8.17.tar.gz; \
##   tar -xvf redis-2.8.17.tar; \
##   cd /data/redis-2.8.17; \
##   ./configure; \
##   make; \
##   make install; \
##   cd /data; \
##   rm -R /data/redis-2.8.17
## 
## # install our test gems
## COPY Gemfile /data/
## COPY Gemfile.lock /data/
## RUN \
##   cd /data; \
##   bundle config --global frozen 1; \
##   bundle install --without production

