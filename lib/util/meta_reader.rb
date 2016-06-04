
module MovieMasher
  # used to parse file's meta data
  class MetaReader < Hashable
    def initialize(path)
      # sequence outputs point to a directory
      path = Dir[Path.concat path, '*'].first if File.directory?(path)
      @path = path
      super {}
    end
    def [](symbol)
      @hash[symbol] ||= _meta(symbol)
      super
    end
    def _meta(symbol)
      s = ffmpeg
      metas = s.split('Metadata:')
      metas.shift
      unless metas.empty?
        sym_str = symbol.id2name
        metas.each do |meta|
          lines = meta.split "\n"
          lines.shift if lines.first.strip.empty?
          first_line = lines.first
          pad = first_line.match(/([\s]+)[\S]/)[1]
          lines.each do |line|
            break unless line.start_with? pad
            pair = line.split(':').map(&:strip)
            return pair.last if pair.first == sym_str
          end
        end
      end
      ''
    end
    def _info
      Info.get(@path, __callee__.id2name)
    end
    alias audio _info
    alias dimensions _info
    alias duration _info
    alias video_duration _info
    alias audio_duration _info
    alias type _info
    alias fps _info
    alias ffmpeg _info
    alias sox _info
    alias http _info
  end
end
