# frozen_string_literal: true

module MovieMasher
  # a job represented as a set of FFdynamic API requests
  class Dynamic
    class << self
    
    end
    
    attr_reader :job, :output
    
    def initialize(job, output)
      @job = job
      @output = output
    end

    def to_h

      output_type = output[:type]
      return unless Type::VIDEO == output_type
      
      
      
      width, height = output.dimensions.split('x')

      result = { post: {}, puts: [] }
      
      if job.inputs.count == 1 && job.inputs.first.type == Type::MASH
        input = job.inputs.first
        mash = input.mash
        result[:post][:backcolor] = mash.backcolor
        result[:post][:quantize] = mash.quantize
        result[:post][:dimensions] = output.dimensions
        
        result[:puts] = mash.dynamic_puts(job, input, output)
      end
      # puts result
      return result 
      
      
      audio_dur = video_dur = FloatUtil::ZERO
      v_segments = []
      a_segments = []
      avb = output[:av]
      unless AV::AUDIO_ONLY == avb
        v_segments = video_segments
        avb = AV::AUDIO_ONLY if v_segments.empty?
      end
      unless AV::VIDEO_ONLY == avb
        a_segments = audio_segments
        avb = AV::VIDEO_ONLY if a_segments.empty?
      end
      v_segments.each do |segment|
        result[:puts] << segment.put_request
      end

      a_segments.each do |segment|
        result[:puts] << segment.put_request
      end

      result
    end

    def __audio_raw(segments)
      segment = segments.first
      __raise_if_negative(segment[:start], "negative start time #{segment}")
      __raise_if_zero(segment[:length], "zero length #{segment}")
      raw = (segments.length == 1)
      raw &&= segment[:loop].nil? || (segment[:loop] == 1)
      raw &&= !Mash.gain_changes(segment[:gain])
      raw &&= FloatUtil.cmp(segment[:start], FloatUtil::ZERO)
      raw
    end

    def audio_segments
      segments = []
      job.inputs.each do |input|
        next if input[:no_audio]

        case input[:type]
        when Type::VIDEO, Type::AUDIO
          segment = input.slice(*Input::Asset::KEYS_AV_SEGMENT) # type offset length cached_file duration gain loop
          segment[:start] = input[:start]
          segments << segment
        when Type::MASH
          quantize = input[:mash][:quantize]
          audio_clips = Mash.clips_having_audio(input[:mash])
          audio_clips.each do |clip|
            media = Mash.media(input[:mash], clip[:id])
            unless media
              raise(Error::JobInput, "couldn't find media #{clip[:id]}")
            end
            next if clip[:no_audio] ||= media[:no_audio]

            segment = clip.slice(*Input::Asset::KEYS_AV_SEGMENT)
            segment[:start] = input[:start].to_f
            segment[:start] += (clip[:frame].to_f / quantize)
            segment[:cached_file] = media[:cached_file]
            segment[:duration] = media[:duration]
            segments << segment
          end
        end
      end
      segments
    end

    def video_segments
      segments = []
      job.inputs.each do |input|
        next if input[:no_video]

        case input[:type]
        when Type::MASH
          Mash.video_ranges(input[:mash]).each do |range|
            segments << __mash_range_segment(input, range)
          end
        when Type::VIDEO, Type::IMAGE
          segments << Job::Segment::Flat.create(job, output, input)
        end
      end
      segments
    end

    def __mash_range_segment(input, range)
      mash = input[:mash]
      segment = Job::Segment::Mash.create(job, output, input, range)
      clips = Mash.clips_in_range(mash, range, Type::VIDEO)

      transition_clip, transition_clips = __transition(clips, mash)

      if transition_clip
        if transition_clips.length > 2
          raise(Error::JobInput, "transitioning too many clips in #{range}")
        end

        transition_layer = segment.add_new_layer(transition_clip)
        transition_clips.each { |clip| transition_layer.add_new_layer(clip) }
      end

      clips.each do |clip|
        next if transition_clip && clip[:track].zero?
        next unless Type::VISUALS.include?(clip[:type])

        segment.add_new_layer(clip)
      end

      segment
    end


    def __copy_raw_from_media(clip, mash)
      return unless Type::RAW_VISUALS.include?(clip[:type])

      media = Mash.media(mash, clip[:id])
      raise(Error::JobInput, "couldn't find media #{clip[:id]}") unless media

      # media props were copied to clip BEFORE file was cached, so do now
      clip[:cached_file] = media[:cached_file]
      raise("no cached_file #{media}") unless clip[:cached_file]

      clip[:no_video] ||= media[:no_video]
      clip[:dimensions] = media[:dimensions]
      raise("couldn't find dimensions #{media}") unless clip[:dimensions]
    end


    def __transition(clips, mash)
      transition_clip = false
      transition_clips = []
      clips.each do |clip|
        __copy_raw_from_media(clip, mash)
        if Type::TRANSITION == clip[:type]
          if transition_clip
            raise(Error::JobInput, "multiple transitions in #{range}")
          end

          transition_clip = clip
        elsif clip[:track].zero?
          transition_clips << clip
        end
      end
      [transition_clip, transition_clips]
    end

  end
end
