FROM ruby:2.7
MAINTAINER Movie Masher <support@moviemasher.com>

ENV HOME /root

# install tools and helpers
RUN apt-get update && apt-get install -y \
  apt-utils \
  build-essential \
  cmake \
  git \
  subversion \
  wget \
  yasm \
  nasm

# install video libs and plugins
RUN apt-get update && apt-get install -y \
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
  ecasound \
  libmad0-dev \
  libid3tag0-dev \
  libboost-all-dev

WORKDIR /data

RUN \
  cd /data; \
  git clone https://github.com/uclouvain/openjpeg.git; \
  mkdir openjpeg/build; \
  cd openjpeg/build; \
  cmake .. -DCMAKE_BUILD_TYPE=Release; \
  make; \
  make install; \
  rm -R /data/openjpeg

# pull, configure, make and install x264
RUN \
  cd /data; \
  git clone https://code.videolan.org/videolan/x264.git; \
  cd /data/x264; \
  ./configure --prefix=/usr --enable-shared; \
  make; \
  make install; \
  rm -R /data/x264

# pull, configure, make and install most recent ffmpeg
RUN \
  cd /data; \
  wget https://ffmpeg.org/releases/ffmpeg-4.2.4.tar.gz; \
  tar -xzvf ffmpeg-4.2.4.tar.gz; \
  cd /data/ffmpeg-4.2.4; \
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
  rm -R /data/ffmpeg-4.2.4;

# needed for binaries to find libraries
RUN ldconfig

# install audiowaveform to build waveform PNGs
RUN \
  cd /data; \
  git clone https://github.com/bbc/audiowaveform.git; \
  mkdir audiowaveform/build; \
  cd audiowaveform/build; \
  cmake -D ENABLE_TESTS=0 ..; \
  make; \
  make install; \
  audiowaveform --help

# install our production gems
COPY Gemfile /data/
RUN \
  bundle install;

# copy everything except what's caught by .dockerignore
COPY . /mnt/moviemasher.rb/
WORKDIR /mnt/moviemasher.rb

# install our entry point, with default command
CMD ["moviemasher"]
ENTRYPOINT ["config/docker/entrypoint.rb"]

# clean up apt and temporary directories
RUN apt-get clean; rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# expose all our configurable directories as potential mount points
VOLUME /tmp/moviemasher/queue
VOLUME /tmp/moviemasher/log
VOLUME /tmp/moviemasher/render
VOLUME /tmp/moviemasher/download
VOLUME /tmp/moviemasher/error

