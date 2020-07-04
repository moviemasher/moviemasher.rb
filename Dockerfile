FROM ruby:2.2
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


WORKDIR /data

RUN \
  cd /data; \
  wget https://github.com/uclouvain/openjpeg/archive/version.2.1.tar.gz; \
  tar -xzvf version.2.1.tar.gz; \
  cd /data/openjpeg-version.2.1; \
  cmake .; \
  make; \
  make install; \
  rm -R /data/openjpeg-version.2.1

# latest nasm required for x264
RUN \
  cd /data; \
  wget http://www.nasm.us/pub/nasm/releasebuilds/2.13.02/nasm-2.13.02.tar.gz; \
  tar -xzvf nasm-2.13.02.tar.gz; \
  cd /data/nasm-2.13.02; \
  ./configure; \
  make; \
  make install; \
  checkinstall --pkgname=nasm --pkgversion="2.13.02" --backup=no --deldoc=yes --fstrans=no --default


# pull, configure, make and install x264
RUN \
  cd /data; \
  git clone https://code.videolan.org/videolan/x264.git; \
  cd /data/x264; \
  git checkout ba24899b0bf23345921da022f7a51e0c57dbe73d; \
  ./configure --prefix=/usr --enable-shared; \
  make; \
  make install; \
  rm -R /data/x264

# pull, configure, make and install most recent ffmpeg
RUN \
  cd /data; \
  wget https://ffmpeg.org/releases/ffmpeg-3.4.1.tar.gz; \
  tar -xzvf ffmpeg-3.4.1.tar.gz; \
  cd /data/ffmpeg-3.4.1; \
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
  rm -R /data/ffmpeg-3.4.1;

# needed for binaries to find libraries
RUN ldconfig

# install our production gems
COPY Gemfile /data/
RUN \
  cd /data; \
  bundle install;

# copy, make and install wav2png
COPY bin/wav2png/* /data/wav2png/
RUN \
  cd /data/wav2png; \
  make; \
  mv wav2png /usr/bin/; \
  rm -R /data/wav2png

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

