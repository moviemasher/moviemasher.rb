
require 'RMagick'

module MagickGenerator
	R4x3 = '4x3'
	R16x9 = '16x9'
	R3x2 = '3x2'
	R1x1 = '1x1'
	RATIOS = [R4x3, R16x9] #, R3x2, R1x1
	SIZES = ['XL', 'LG', 'MD', 'SM', 'XS']

	XL16x9W = 1536
	XL16x9H = 864
	LG16x9W = 1280
	LG16x9H = 720
	MD16x9W = 768
	MD16x9H = 432
	SM16x9W = 512
	SM16x9H = 288
	XS16x9W = 256
	XS16x9H = 144

	XL16x9 = '1536x864'
	LG16x9 = '1280x720'
	MD16x9 = '768x432'
	SM16x9 = '512x288'
	XS16x9 = '256x144'

	XL4x3W = 1280
	XL4x3H = 960
	LG4x3W = 640
	LG4x3H = 480
	MD4x3W = 320
	MD4x3H = 240
	SM4x3W = 160
	SM4x3H = 120
	XS4x3W = 80
	XS4x3H = 60

	MD1x1W = 512
	MD1x1H = 512
	SM1x1W = 320
	SM1x1H = 320

	XL4x3 = '1280x960'
	LG4x3 = '640x480'
	MD4x3 = '320x240'
	SM4x3 = '160x120'
	XS4x3 = '80x60'

	RED = '#FF0000'
	GREEN = '#00FF00'
	BLUE = '#0000FF'
	YELLOW = '#FFFF00'
	PURPLE = '#FF00FF'
	AQUA = '#00FFFF'

	@@colors_by_extension = Hash.new
	Directory = "#{__dir__}/../../tmp/spec/magick"
	
	def self.output_color(color, extension = 'png')
		key = "#{extension}-#{color}"
		unless @@colors_by_extension[key]
			height = width = 32
			file_path = "#{Directory}/#{width}x#{height}-#{color[1..-1]}.#{extension}"
			image = canvas :width => width, :height => height, :back => color
			FileUtils.makedirs Directory
			image.write(file_path)
			@@colors_by_extension[key] = color_of_file(file_path)
		end
		@@colors_by_extension[key]
	end
	def self.color_frames video_file
		colors = Array.new
		if video_file and File.exists? video_file
			images = Magick::ImageList.new.read(video_file)
			last_color = nil
			frames = [0,0]
			frame = 0
			images.each do |image|
				image_color = color_of_image image
				unless last_color == image_color
					last_color = image_color
					frames = [frame, 0]
					colors << {:color => image_color, :frames => frames}
				end
				frames[1] += 1
				frame += 1
			end
		end
		colors
	end
	def self.color_of_file path
		color_of_image Magick::Image.read(path).first
	end
	def self.color_of_image image
		hist = image.color_histogram
		if 1 < hist.keys.length
			puts "#{self.name} Warning: quantizing #{hist.keys.length} colors in #{path}"
			image.quantize(1, Magick::RGBColorspace, Magick::NoDitherMethod)
			hist = image.color_histogram
		end
		hist.keys.first.to_color(Magick::AllCompliance, false, 8, true)
	end
	def self.canvas options = Hash.new
		options[:width] = LG16x9W unless options[:width]
		options[:height] = LG16x9H unless options[:height]
		options[:back] = GREEN unless options[:back]
		options[:back] = "##{options[:back]}" if options[:back].length == 6
		
		if options[:grid]
			Magick::Image.new(options[:width], options[:height], Magick::HatchFill.new(options[:back], 'white', 100))
		else
			Magick::Image.new(options[:width], options[:height]) {
				self.background_color = options[:back] unless options[:grid]
			}
		end
	end
	def self.generate file_name
		#puts "generate #{file_name}"
		extension = File.extname file_name
		file_name[extension] = ''
		bits = file_name.split('-')
		extension = extension[1..-1]
		is_image = ['jpg', 'png'].include? extension
		options = {
			:size => 'sm',
			:ratio => R16x9,
			:back => GREEN, 
			:grid => false
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
		image_file options
	end
	def self.parse_options options
		unless options[:width] and options[:height]
			up_size = options[:size]
			ratio = options[:ratio]
			if up_size and ratio
				w = 'W'
				h = 'H'
				ratios = ratio.split('x').map { |n| n.to_i }
				if ratios.first < ratios.last
					ratio = ratios.reverse.join 'x'
					w = 'H'
					h = 'W'
				end
				options[:width] = const_get("#{up_size.upcase}#{ratio}#{w}".to_sym) unless options[:width]
				options[:height] = const_get("#{up_size.upcase}#{ratio}#{h}".to_sym) unless options[:height] 
			end
		end
	end
	def self.image_file options = Hash.new
		parse_options options
		options[:extension] = 'png' unless options[:extension]
		options[:extension] = options[:extension][1..-1] if options[:extension].start_with? '.'
		image = canvas options
		
		file_path = "#{Directory}/"
		file_path += Digest::SHA2.new(256).hexdigest(options.inspect) 
		file_path += ".#{options[:extension]}"
		FileUtils.makedirs Directory
		
		image.write(file_path) do |opts|
			opts.delay = 100 * options[:duration].to_i if options[:duration]
		end
		file_path
	end
	def self.ratio_image_file options = Hash.new
		options[:width] = LG16x9W unless options[:width]
		options[:outer] = R16x9 unless options[:outer]
		options[:inner] = R4x3 unless options[:inner]
		options[:back] = GREEN unless options[:back]
		options[:fore] = RED unless options[:fore]
		options[:extension] = 'png' unless options[:extension]

		outer_a = options[:outer].split('x').map { |s| s.to_f }
		inner_a = options[:inner].split('x').map { |s| s.to_f }
		
		options[:width] = options[:width].to_i
		unit = (options[:width].to_f / outer_a.first)
		options[:height] = (unit * outer_a.last).to_i
		ratio = [outer_a.first / inner_a.first, outer_a.last / inner_a.last].min
		inner_width = (inner_a.first * unit * ratio).to_i
		inner_height = (inner_a.last * unit * ratio).to_i
		
		x = ((options[:width] - inner_width).to_f / 2.0).to_i
		y = ((options[:height] - inner_height).to_f / 2.0).to_i

		image = canvas options
		Magick::Image.new(options[:width], options[:height]) { self.background_color = options[:back] }

		rect = Magick::Draw.new
		rect.fill(options[:fore])
		rect.rectangle(x, y, x + inner_width, y + inner_height)
		rect.draw(image)
		
		file_path = "#{Directory}/#{options[:width]}x#{options[:height]}-#{inner_width}x#{inner_height}.#{options[:extension]}"
		FileUtils.makedirs Directory
		image.write(file_path)
		file_path
	end
end