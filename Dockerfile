FROM amazonlinux
MAINTAINER Movie Masher <support@moviemasher.com>

# # # # # # # # # # # # # # # #
# DEFINE DIRECTORIES
ARG DIR_BINARY=/usr/bin
ARG DIR_BUILD=/usr
ARG DIR_SOURCE=/root

# # # # # # # # # # # # # # # #
# DEFINE BUILD TOOLS
ARG BUILD_TOOLS="wget gcc git cmake make gcc-c++ libtool tar bzip2 bzip2-devel"
ARG BUILD_LIBS="freetype-devel fontconfig-devel fribidi-devel frei0r-devel libogg-devel libsamplerate-devel libsndfile-devel speex-devel libtheora-devel libvorbis-devel libmad-devel libid3tag-devel"

# # # # # # # # # # # # # # # #
# DEFINE VERSIONS
ARG VERSION_AMR=0.1.3
ARG VERSION_BUNDLER=2.1.4
ARG VERSION_ECA=2.9.1
ARG VERSION_FFMPEG=4.2.4
ARG VERSION_LAME=3.100
ARG VERSION_NASM=2.14.02
ARG VERSION_OPUS=1.3.1
ARG VERSION_RUBY=2.6
ARG VERSION_SOX=14.4.1
ARG VERSION_XVID=1.3.5
ARG VERSION_YASM=1.3.0

COPY Gemfile $DIR_SOURCE

# # # # # # # # # # # # # # # # #
# # INSTALL FFMPEG AND ECASOUND
RUN set -e ;\
	yum update -y ; \
	amazon-linux-extras install -y epel ; \
	yum install -y $BUILD_TOOLS $BUILD_LIBS ; \
	cd $DIR_SOURCE ; \
	curl --silent -O -L https://www.nasm.us/pub/nasm/releasebuilds/$VERSION_NASM/nasm-$VERSION_NASM.tar.bz2 ; \
	tar xjf nasm-$VERSION_NASM.tar.bz2 ; \
	cd nasm-$VERSION_NASM ; \
	./autogen.sh ; \
	./configure --prefix=$DIR_BUILD --bindir=$DIR_BINARY ; \
	make ; \
	make install ; \
	whereis nasm ; \
	cd $DIR_SOURCE ; \
	curl --silent -O -L https://www.tortall.net/projects/yasm/releases/yasm-$VERSION_YASM.tar.gz ; \
	tar xzf yasm-$VERSION_YASM.tar.gz ; \
	cd yasm-$VERSION_YASM ; \
	./configure --prefix=$DIR_BUILD --bindir=$DIR_BINARY ; \
	make ; \
	make install ; \
	whereis yasm ; \
	cd $DIR_SOURCE ; \
	curl --silent -O -L https://downloads.sourceforge.net/project/lame/lame/$VERSION_LAME/lame-$VERSION_LAME.tar.gz ; \
	tar xzf lame-$VERSION_LAME.tar.gz ; \
	cd lame-$VERSION_LAME ; \
	./configure --prefix=$DIR_BUILD --bindir=$DIR_BINARY --disable-shared --enable-nasm ; \
	make ; \
	make install ; \
	cd $DIR_SOURCE ; \
	curl --silent -O -L https://archive.mozilla.org/pub/opus/opus-$VERSION_OPUS.tar.gz ; \
	tar xzf opus-$VERSION_OPUS.tar.gz ; \
	cd opus-$VERSION_OPUS ; \
	./configure --prefix=$DIR_BUILD --disable-shared ; \
	make ; \
	make install ; \
	cd $DIR_SOURCE ; \
	wget --quiet http://downloads.xvid.org/downloads/xvidcore-$VERSION_XVID.tar.gz ; \
	tar -zxf xvidcore-$VERSION_XVID.tar.gz ; \
	cd xvidcore/build/generic ; \
	./configure --prefix=$DIR_BUILD ; \
	make ; \
	make install ; \
	cd $DIR_SOURCE ; \
	wget --quiet http://downloads.sourceforge.net/project/opencore-amr/opencore-amr/opencore-amr-$VERSION_AMR.tar.gz ; \
	tar -xf opencore-amr-$VERSION_AMR.tar.gz ; \
	cd opencore-amr-$VERSION_AMR ; \
	./configure --prefix=$DIR_BUILD --disable-shared ; \
	make ; \
	make install ; \
	cd $DIR_SOURCE ; \
	git clone --depth 1 https://chromium.googlesource.com/webm/libvpx.git ; \
	cd libvpx ; \
	./configure --prefix=$DIR_BUILD --disable-examples --disable-unit-tests --enable-vp9-highbitdepth --as=yasm ; \
	make ; \
	make install ; \
	cd $DIR_SOURCE ; \
	git clone --depth 1 https://code.videolan.org/videolan/x264.git ; \
	cd x264 ; \
  ./configure --prefix=$DIR_BUILD --bindir=$DIR_BINARY --enable-static ; \
	make ; \
	make install ; \
	whereis x264 ; \
	cd $DIR_SOURCE ; \
	git clone https://github.com/uclouvain/openjpeg.git ; \
	mkdir openjpeg/build ; \
	cd openjpeg/build ; \
	cmake .. -DCMAKE_INSTALL_PREFIX=$DIR_BUILD -DCMAKE_BUILD_TYPE=Release ; \
	make ; \
	make install ; \
	ldconfig ; \
	cd $DIR_SOURCE ; \
	wget --quiet https://ffmpeg.org/releases/ffmpeg-$VERSION_FFMPEG.tar.gz ; \
	tar -xzf ffmpeg-$VERSION_FFMPEG.tar.gz ; \
	cd ffmpeg-$VERSION_FFMPEG ; \
	PATH="$DIR_BINARY:$PATH" \
	PKG_CONFIG_PATH=$DIR_BUILD/lib/pkgconfig \
	./configure \
  --prefix=$DIR_BUILD \
  --pkg-config-flags="--static" \
  --extra-cflags="-I$DIR_BUILD/include" \
  --extra-ldflags="-L$DIR_BUILD/lib" \
  --extra-libs=-lpthread \
  --extra-libs=-lm \
  --bindir=$DIR_BINARY \
	--enable-libopenjpeg \
	--enable-frei0r \
	--enable-libfontconfig \
	--enable-libfreetype \
	--enable-libfribidi \
	--enable-libmp3lame \
	--enable-libopencore-amrnb \
	--enable-libopencore-amrwb \
	--enable-libspeex \
	--enable-libtheora \
	--enable-libvorbis \
	--enable-libx264 \
	--enable-zlib \
	--enable-libxvid \
  --enable-libvpx \
  --enable-libopus \
	--enable-postproc \
	--enable-pthreads \
	--enable-version3 \
	--enable-gpl ; \
	make ; \
	make install ; \
	whereis ffmpeg ; \
	cd $DIR_SOURCE ; \
	wget --quiet http://sourceforge.net/projects/sox/files/sox/$VERSION_SOX/sox-$VERSION_SOX.tar.gz ; \
	tar -zxf sox-$VERSION_SOX.tar.gz ; \
	cd sox-$VERSION_SOX ; \
	./configure --disable-shared --prefix=$DIR_BUILD --bindir=$DIR_BINARY ; \
	make -s ; \
	make install ; \
	whereis sox ; \
	cd $DIR_SOURCE ; \
	wget --quiet http://ecasound.seul.org/download/ecasound-$VERSION_ECA.tar.gz ; \
	tar -xzf ecasound-$VERSION_ECA.tar.gz ; \
	cd ecasound-$VERSION_ECA ; \
	./configure --prefix=$DIR_BUILD --bindir=$DIR_BINARY --enable-rubyecasound=no --enable-pyecasound=none ; \
	make ; \
	make install ; \
	whereis ecasound ; \
	cd $DIR_SOURCE ; \
	amazon-linux-extras install -y ruby$VERSION_RUBY ; \
	yum install -y ruby-devel ; \
	BUNDLE_SILENCE_ROOT_WARNING=1 \
	gem install bundler --version $VERSION_BUNDLER ; \
	bundle install ; \
	yum remove -y $BUILD_TOOLS $BUILD_LIBS ; \
 	yum clean all ; \
	rm -rf /tmp/* /var/tmp/* /var/cache/* $DIR_SOURCE/*
	
COPY ./service /mnt/moviemasher.rb/service
COPY ./lib /mnt/moviemasher.rb/lib
COPY ./config /mnt/moviemasher.rb/config

WORKDIR /mnt/moviemasher.rb
CMD ["moviemasher"]
ENTRYPOINT ["config/docker/entrypoint.rb"]

# RUN nasm --version ; \
# 	yasm --version ; \
# 	sox --version ; \
# 	x264 --version ; \
# 	ecasound --version ; \
# 	ffmpeg -version 
