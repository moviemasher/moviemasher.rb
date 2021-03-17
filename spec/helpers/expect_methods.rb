def expect_s3_file(bucket_name, path)
  bucket = MovieMasher::Service.instance(:upload,
                                         :s3).s3_resource.bucket(bucket_name)
  object = bucket.object(path)
  expect(object).to be_exists
end
def expect_color_image(color, path)
  ext = File.extname(path)
  ext = ext[1..-1]
  expected_color = MagickGenerator.output_color(color, ext)
  expect(MagickGenerator.color_of_file(path)).to eq expected_color
end
def expect_dimensions(destination_file, dimensions)
  expect(MovieMasher::Info.get(destination_file, 'dimensions')).to eq dimensions
end
def expect_duration(destination_file, job)
  duration = MovieMasher::Info.get(destination_file, 'duration').to_f
  job_duration = job[:duration]
  # puts "duration: #{duration} job_duration: #{job_duration}"
  
  puts job[:inputs].map(&:to_json) if (job_duration - duration).abs > 0.1
  expect(duration).to be_within(0.1).of job_duration
end
def expect_color_video(color, video_file)
  video_duration = MovieMasher::Info.get(video_file, 'duration').to_f
  video_rate = MovieMasher::Info.get(video_file, 'fps').to_f
  frames = (video_rate * video_duration).to_i
  expect_colors_video([{ color: color, frames: [0, frames] }], video_file)
end
def expect_colors_video(colors, video_file)
  color_frames = MagickGenerator.color_frames(video_file)
  puts "#{color_frames}\n#{colors}" unless color_frames.length == colors.length
  expect(color_frames.length).to eq colors.length
  color_frames.length.times do |i|
    reported = color_frames[i]
    expected = colors[i]
    next if reported == expected

    puts "#{reported} != #{expected}" if reported[:frames] != expected[:frames]
    expect(reported[:frames]).to eq expected[:frames]
    reported_color = reported[:color]
    expected_color = MagickGenerator.output_color(expected[:color], 'jpg')
    next if expected_color == reported_color

    expected_color = MagickGenerator.output_color(expected[:color], 'png')
    next if expected_color == reported_color

    puts video_file
    expect(reported).to eq expected
  end
end
def expect_http_file(file_name)
  expect(File.exist?("#{DIR_HTTP_POSTS}/#{file_name}")).to be_truthy
end
def expect_local_file(file_name)
  expect(File.exist?("#{DIR_LOCAL_POSTS}/#{file_name}")).to be_truthy
end
def expect_fps(destination_file, fps)
  expect(MovieMasher::Info.get(destination_file, 'fps').to_i).to eq fps.to_i
end
