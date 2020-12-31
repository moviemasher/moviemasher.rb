require 'rmagick'

module MagickGenerator
  R4X3 = '4x3'.freeze
  R16X9 = '16x9'.freeze
  R3X2 = '3x2'.freeze
  R1X1 = '1x1'.freeze
  RATIOS = [R4X3, R16X9].freeze
  SIZES = %w[XL LG MD SM XS].freeze

  XL16X9W = 1536
  XL16X9H = 864
  LG16X9W = 1280
  LG16X9H = 720
  MD16X9W = 768
  MD16X9H = 432
  SM16X9W = 512
  SM16X9H = 288
  XS16X9W = 256
  XS16X9H = 144

  XL16X9 = '1536x864'.freeze
  LG16X9 = '1280x720'.freeze
  MD16X9 = '768x432'.freeze
  SM16X9 = '512x288'.freeze
  XS16X9 = '256x144'.freeze

  XL4X3W = 1280
  XL4X3H = 960
  LG4X3W = 640
  LG4X3H = 480
  MD4X3W = 320
  MD4X3H = 240
  SM4X3W = 160
  SM4X3H = 120
  XS4X3W = 80
  XS4X3H = 60

  MD1X1W = 512
  MD1X1H = 512
  SM1X1W = 320
  SM1X1H = 320

  XL4X3 = '1280x960'.freeze
  LG4X3 = '640x480'.freeze
  MD4X3 = '320x240'.freeze
  SM4X3 = '160x120'.freeze
  XS4X3 = '80x60'.freeze

  RED = '#FF0000'.freeze
  GREEN = '#00FF00'.freeze
  BLUE = '#0000FF'.freeze
  YELLOW = '#FFFF00'.freeze
  PURPLE = '#FF00FF'.freeze
  AQUA = '#00FFFF'.freeze

  DIRECTORY = File.expand_path("#{__dir__}/../../tmp/spec/magick").freeze

  def self.canvas(options = {})
    options[:width] = LG16X9W unless options[:width]
    options[:height] = LG16X9H unless options[:height]
    options[:back] = GREEN unless options[:back]
    options[:back] = "##{options[:back]}" if options[:back].length == 6

    if options[:grid]
      fill = Magick::HatchFill.new(options[:back], 'white', 100)
      Magick::Image.new(options[:width], options[:height], fill)
    else
      Magick::Image.new(options[:width], options[:height]) do
        self.background_color = options[:back] unless options[:grid]
      end
    end
  end
  def self.color_frames(video_file)
    colors = []
    if video_file && File.exist?(video_file)
      images = Magick::ImageList.new.read(video_file)
      last_color = nil
      frames = [0, 0]
      frame = 0
      images.each do |image|
        image_color = color_of_image(image)
        unless last_color == image_color
          last_color = image_color
          frames = [frame, 0]
          colors << { color: image_color, frames: frames }
        end
        frames[1] += 1
        frame += 1
      end
    end
    colors
  end
  def self.color_of_file(path)
    color_of_image Magick::Image.read(path).first
  end
  def self.color_of_image(image)
    hist = image.color_histogram
    if 1 < hist.keys.length
      puts "#{name} Warning: quantizing #{hist.keys.length} colors"
      image.quantize(1, Magick::RGBColorspace, Magick::NoDitherMethod)
      hist = image.color_histogram
    end
    hist.keys.first.to_color(Magick::AllCompliance, false, 8, true)
  end
  def self.generate(file_name)
    # puts "generate #{file_name}"
    extension = File.extname(file_name)
    file_name[extension] = ''
    bits = file_name.split('-')
    extension = extension[1..-1]
    is_image = %w[jpg png].include?(extension)
    options = {
      size: 'sm',
      ratio: R16X9,
      back: GREEN,
      grid: false
    }
    options[:duration] = bits.shift unless is_image
    options[:extension] = extension
    bits.each do |bit|
      case bit.length
      when 2
        options[:size] = bit
      when 6
        options[:back] = bit
      else
        if 'grid' == bit
          options[:grid] = true
        elsif bit =~ /[0-9]+x[0-9]+/
          options[:ratio] = bit
        else
          options[:back] = bit unless options[:back]
        end
      end
    end
    image_file(options)
  end
  def self.image_file(options = {})
    parse_options options
    options[:extension] = 'png' unless options[:extension]
    if options[:extension].start_with?('.')
      options[:extension] = options[:extension][1..-1]
    end
    image = canvas(options)

    file_path = "#{DIRECTORY}/"
    file_path += Digest::SHA2.new(256).hexdigest(options.inspect)
    file_path += ".#{options[:extension]}"
    FileUtils.makedirs(DIRECTORY)
    image.write(file_path) do |opts|
      opts.delay = 100 * options[:duration].to_i if options[:duration]
    end
    file_path
  end
  def self.output_color(color, extension = 'png')
    height = width = 32
    file_path = "#{DIRECTORY}/#{width}x#{height}-#{color[1..-1]}.#{extension}"
    unless File.exist?(file_path)
      image = canvas(width: width, height: height, back: color)
      FileUtils.makedirs(DIRECTORY)
      image.write(file_path)
    end
    color_of_file(file_path)
  end
  def self.parse_options(options)
    unless options[:width] && options[:height]
      up_size = options[:size]
      ratio = options[:ratio]
      if up_size && ratio
        w = 'W'
        h = 'H'
        ratios = ratio.split('x').map(&:to_i)
        if ratios.first < ratios.last
          ratio = ratios.reverse.join('x')
          w = 'H'
          h = 'W'
        end
        unless options[:width]
          options[:width] = const_get("#{up_size}#{ratio}#{w}".upcase)
        end
        unless options[:height]
          options[:height] = const_get("#{up_size}#{ratio}#{h}".upcase)
        end
      end
    end
  end
  def self.ratio_image_file(options = {})
    options[:width] = LG16X9W unless options[:width]
    options[:outer] = R16X9 unless options[:outer]
    options[:inner] = R4X3 unless options[:inner]
    options[:back] = GREEN unless options[:back]
    options[:fore] = RED unless options[:fore]
    options[:extension] = 'png' unless options[:extension]

    outer_a = options[:outer].split('x').map(&:to_f)
    inner_a = options[:inner].split('x').map(&:to_f)

    options[:width] = options[:width].to_i
    unit = (options[:width].to_f / outer_a.first)
    options[:height] = (unit * outer_a.last).to_i
    ratio = [outer_a.first / inner_a.first, outer_a.last / inner_a.last].min
    inner_width = (inner_a.first * unit * ratio).to_i
    inner_height = (inner_a.last * unit * ratio).to_i

    x = ((options[:width] - inner_width).to_f / 2.0).to_i
    y = ((options[:height] - inner_height).to_f / 2.0).to_i

    image = canvas(options)
    Magick::Image.new(options[:width], options[:height]) do
      self.background_color = options[:back]
    end

    rect = Magick::Draw.new
    rect.fill(options[:fore])
    rect.rectangle(x, y, x + inner_width, y + inner_height)
    rect.draw(image)
    dims = "#{options[:width]}x#{options[:height]}"
    inner_dims = "#{inner_width}x#{inner_height}"
    file_path = "#{DIRECTORY}/#{dims}-#{inner_dims}.#{options[:extension]}"
    FileUtils.makedirs(DIRECTORY)
    image.write(file_path)
    file_path
  end
end
