# frozen_string_literal: true

module MovieMasher
  # Input#source of mash inputs, representing a collection of #media 
  # arranged on #audio and #video tracks.
  class Mash < Hashable
    class << self
      def clip_has_audio(clip)
        has = false
        unless clip[:no_audio]
          url =
            case clip[:type]
            when Type::AUDIO
              clip[:source] || clip[:audio]
            when Type::VIDEO
              clip[:source] || __nonzero_audio(clip)
            end
          if url
            has = !clip[:gain]
            has ||= !__gain_mutes(clip[:gain])
          end
        end
        has
      end

      def clips_having_audio(mash)
        clips = []
        Type::TRACKS.each do |track_type|
          mash[track_type.to_sym].each do |track|
            track[:clips].each do |clip|
              clips << clip if clip_has_audio(clip)
            end
          end
        end
        clips
      end

      def clips_in_range(mash, range, track_type = nil, track_number = nil)
        track_types = track_type ? [track_type] : [Type::AUDIO, Type::VIDEO]
        
        
        in_range = []
        track_types.each do |type|
          mash[type.to_sym].each do |track|
            next if track_number && track_number != track[:index]
              
            track[:clips].each do |clip|
              in_range << clip if range.intersection(clip[:range])
            end
          end
        end
        in_range.sort do |a, b|
          if a[:track] == b[:track]
            a[:frame] <=> b[:frame]
          else
            a[:track] <=> b[:track]
          end
        end
      end
      
      def duration(mash)
        mash[:length] / mash[:quantize]
      end

      def gain_changes(gain)
        does = false
        if gain.is_a?(String) && gain.include?(',')
          gains = gain.split ','
          (gains.length / 2).times do |i|
            does = !FloatUtil.cmp(gains[1 + i * 2].to_f, Gain::None)
            break if does
          end
        else
          does = !FloatUtil.cmp(gain.to_f, Gain::None)
        end
        does
      end

      def hash?(hash)
        isa = false
        if hash.is_a?(Hash) || hash.is_a?(Mash)
          medias = __ob_prop(:media, hash)
          if medias.is_a?(Array)
            video_tracks = __ob_prop(:video, hash)
            audio_tracks = __ob_prop(:audio, hash)
            isa = (video_tracks || audio_tracks)
          end
        end
        isa
      end

      def audio?(mash)
        Type::TRACKS.each do |track_type|
          mash[track_type.to_sym].each do |track|
            track[:clips].each do |clip|
              return true if clip_has_audio(clip)
            end
          end
        end
        false
      end

      def video?(mash)
        mash && mash[:video] && mash[:video].any? do |track|
          track[:clips]&.any?
        end
      end

      def init_hash(mash)
        Hashable._init_key mash, :backcolor, 'black'
        mash[:quantize] ||= FloatUtil::ONE
        mash[:quantize] = mash[:quantize].to_f
        mash[:media] ||= []
        longest = FloatUtil::ZERO
        Type::TRACKS.each do |track_type|
          track_sym = track_type.to_sym
          mash[track_sym] ||= []
          mash[track_sym].each_with_index do |track, track_index|
            track[:clips] ||= []
            track[:clips].map! do |clip|
              clip = __init_clip clip, mash, track_index, track_type
              if AV.includes?(clip[:av], Type::VIDEO)
                __init_clip_media(clip[:merger], mash, :merger)
                __init_clip_media(clip[:scaler], mash, :scaler)
                clip[:effects].each do |effect|
                  __init_clip_media(effect, mash, :effect)
                end
              end
              clip
            end
            clip = track[:clips].last
            longest = FloatUtil.max(longest, clip[:range].stop) if clip
            track_index += 1
          end
        end
        
        mash[:length] = longest
        mash
      end

      def init_av_input(input)
        if input[:no_video]
          (input[:no_audio] ? AV::NEITHER : AV::AUDIO_ONLY)
        else
          (input[:no_audio] ? AV::VIDEO_ONLY : AV::BOTH)
        end
      end

      def init_input(input)
        Hashable._init_key(input, :uuid, SecureRandom.uuid)
        __init_input_av(input)
        if AV.includes?(input[:av], Type::VIDEO)
          input[:effects] ||= []
          input[:merger] ||= Defaults.module_for_type(:merger)
          input[:scaler] ||= Defaults.module_for_type(:scaler) unless input[:fill]
          __init_input_fill(input)
        end
        __init_input_source(input)
      end

      def init_mash_input(input)
        return unless hash?(input[:mash])

        input[:mash] = Mash.new(input[:mash])
        input[:mash]&.preflight
        if FloatUtil.cmp(input[:duration], FloatUtil::ZERO)
          input[:duration] = duration(input[:mash])
        end
        input[:no_audio] = !audio?(input[:mash])
        input[:no_video] = !video?(input[:mash])
      end

      def media(mash, ob_or_id)
        return nil unless mash && ob_or_id

        ob_or_id = __ob_prop(:id, ob_or_id) if ob_or_id.is_a?(Hash)
        if ob_or_id
          media_array = __ob_prop(:media, mash)
          if media_array.is_a?(Array)
            media_array.each do |media|
              id = __ob_prop(:id, media)
              return media if id == ob_or_id
            end
          end
        end
        nil
      end

      def media_count_for_clips(mash, clips, referenced)
        referenced ||= {}
        clips&.each do |clip|
          media_id = __ob_prop(:id, clip)
          __media_reference(mash, media_id, referenced)
          reference = referenced[media_id]
          raise("__media_reference with no #{media_id}") unless reference

          media = reference[:media]
          next unless media

          if __modular_media?(media)
            keys = __properties_for_media(media, Type::FONT)
            keys.each do |key|
              font_id = clip[key]
              __media_reference(mash, font_id, referenced, Type::FONT)
            end
          end
          media_type = __ob_prop(:type, media)
          case media_type
          when Type::TRANSITION
            __media_merger_scaler(mash, __ob_prop(:to, media), referenced)
            __media_merger_scaler(mash, __ob_prop(:from, media), referenced)
          when Type::EFFECT, Type::AUDIO
            # do nothing since clip has no effects, merger or scaler
          else
            __media_merger_scaler(mash, clip, referenced)
            effects = __ob_prop(:effects, clip)
            media_count_for_clips(mash, effects, referenced)
          end
        end
      end

      def media_search(type, ob_or_id, mash)
        return unless ob_or_id

        media_ob = nil
        ob_or_id = __ob_prop(:id, ob_or_id) if ob_or_id.is_a?(Hash)
        if ob_or_id
          media_ob = media(mash, ob_or_id) if mash
          media_ob ||= Defaults.module_for_type(type, ob_or_id)
        end
        media_ob
      end

      def video_ranges(mash)
        quantize = mash[:quantize]
        frames = []
        frames << 0
        frames << mash[:length]
        mash[:video].each do |track|
          track[:clips].each do |clip|
            frames << clip[:range].start
            frames << clip[:range].stop
          end
        end
        all_ranges = []
        frames.uniq!
        frames.sort!
        frame = nil
        frames.length.times do |i|
          if frame
            all_ranges << TimeRange.new(frame, quantize, frames[i] - frame)
          end
          frame = frames[i]
        end
        all_ranges
      end

      private

      def __gain_mutes(gain)
        does = true
        if gain.is_a?(String) && gain.include?(',')
          does = true
          gains = gain.split ','
          gains.length.times do |i|
            does = FloatUtil.cmp(gains[1 + i * 2].to_f, Gain::Mute)
            break unless does
          end
        else
          does = FloatUtil.cmp(gain.to_f, Gain::Mute)
        end
        does
      end

      def __init_clip(input, mash, track_index, track_type)
        __init_clip_media(input, mash, track_type)
        __init_clip_range(input, mash)

        input[:length] ||= input[:range].length_seconds
        input[:track] = track_index if track_index

        case input[:type]
        when Type::FRAME
          __init_clip_frame(input, mash)
        when Type::TRANSITION
          __init_clip_transition(input, mash)
        when Type::VIDEO, Type::AUDIO
          input[:trim] ||= 0
          input[:offset] ||= input[:trim].to_f / mash[:quantize]
        end
        init_input(input)
        Clip.create(input)
      end

      def __init_clip_frame(input, mash)
        input[:still] ||= 0
        input[:fps] ||= mash[:quantize]
        if input[:still] + input[:fps] < 2
          input[:quantized_frame] = 0
        else
          still_frame = (input[:still].to_f / input[:fps]).round
          input[:quantized_frame] = mash[:quantize] * still_frame
        end
      end

      def __init_clip_media(clip, mash, type = nil)
        return unless clip

        raise(Error::JobInput, "clip has no id #{clip}") unless clip[:id]

        media = media_search(type, clip, mash)
        unless media
          raise(Error::JobInput, "no #{clip[:id]} #{type || 'media'} found")
        end

        media.each { |k, v| clip[k] = v unless clip[k] }
      end

      def __init_clip_range(input, mash)
        input[:frame] ||= FloatUtil::ZERO
        input[:frame] = input[:frame].to_f
        unless input[:frames] && (input[:frames]).positive?
          raise(Error::JobInput, 'mash clips must have frames')
        end

        input[:range] = TimeRange.new(
          input[:frame], mash[:quantize], input[:frames]
        )
      end

      def __init_clip_transition(input, mash)
        input[:to] ||= {}
        input[:from] ||= {}
        input[:to][:merger] ||= Defaults.module_for_type(:merger)
        input[:from][:merger] ||= Defaults.module_for_type(:merger)
        unless input[:to][:fill]
          input[:to][:scaler] ||= Defaults.module_for_type(:scaler)
        end
        unless input[:from][:fill]
          input[:from][:scaler] ||= Defaults.module_for_type(:scaler)
        end
        __init_clip_media(input[:to][:merger], mash, Type::MERGER)
        __init_clip_media(input[:from][:merger], mash, Type::MERGER)
        __init_clip_media(input[:to][:scaler], mash, Type::SCALER)
        __init_clip_media(input[:from][:scaler], mash, Type::SCALER)
      end

      def __init_input_av(input)
        is_av = __init_input_gain(input)
        # set no_audio and/or no_video when we know for sure
        case input[:type]
        when Type::MASH
          init_mash_input(input)
        when Type::VIDEO
          __init_input_video(input)
        when Type::AUDIO
          Hashable._init_key(input, :loop, 1)
          input[:no_video] = true
        when Type::IMAGE
          input[:no_video] = false
          input[:no_audio] = true
        else
          input[:no_audio] = true
        end
        input[:no_audio] ||= !clip_has_audio(input) if is_av
        input[:av] = init_av_input(input)
        is_av
      end

      def __init_input_gain(input)
        return unless [Type::VIDEO, Type::AUDIO].include?(input[:type])

        # set volume with default of none (no adjustment)
        Hashable._init_key(input, :gain, Gain::None)
        true
      end

      def __init_input_fill(input)
        visual_types = [Type::VIDEO, Type::IMAGE, Type::FRAME]
        return unless visual_types.include?(input[:type])

        Hashable._init_key(input, :fill, Fill::STRETCH)
        true
      end

      def __init_input_source(input)
        source_types = [Type::VIDEO, Type::IMAGE, Type::FRAME, Type::AUDIO]
        return unless source_types.include?(input[:type])

        # set source from url unless defined
        input[:source] ||= input[:url]
        true
      end

      def __init_input_video(input)
        input[:speed] ||= FloatUtil::ONE
        input[:speed] = input[:speed].to_f
        input[:no_audio] = !FloatUtil.cmp(FloatUtil::ONE, input[:speed])
        input[:no_video] = false
      end

      def __media_merger_scaler(mash, object, referenced)
        return unless object

        merger = __ob_prop(Type::MERGER, object)
        if merger
          id = __ob_prop(:id, merger)
          __media_reference(mash, id, referenced, Type::MERGER) if id
        end
        scaler = __ob_prop(Type::SCALER, object)

        return unless scaler

        id = __ob_prop(:id, scaler)
        return unless id

        __media_reference(mash, id, referenced, Type::SCALER)
      end

      def __media_reference(mash, media_id, referenced, type = nil)
        return unless media_id && referenced

        if referenced[media_id]
          referenced[media_id][:count] += 1
        else
          referenced[media_id] = {}
          referenced[media_id][:count] = 1
          referenced[media_id][:media] = media_search(type, media_id, mash)
        end
      end

      def __modular_media?(media)
        case __ob_prop(:type, media)
        when Type::IMAGE, Type::AUDIO, Type::VIDEO, Type::FRAME
          false
        else
          true
        end
      end

      def __nonzero_audio(clip)
        audio = clip[:audio].to_s
        return if audio == '0'

        audio
      end

      def __ob_prop(sym, object)
        prop = nil
        if sym && object && (object.is_a?(Hash) || object.is_a?(Hashable))
          sym = sym.to_sym unless sym.is_a?(Symbol)
          prop = object[sym] || object[sym.id2name]
        end
        prop
      end

      def __properties_for_media(media, type)
        prop_keys = []
        if type && media
          properties = __ob_prop(:properties, media)
          if properties.is_a?(Hash)
            properties.each do |key, property|
              property_type = __ob_prop(:type, property)
              prop_keys << key if type == property_type
            end
          end
        end
        prop_keys
      end
    end

    def segment_frames_dynamic(range = nil)
      range ||= TimeRange.new(0, quantize, length)
      
      # we don't include transitions at all 
      clips_with_transitions = self.class.clips_in_range(self, range)
      clips = clips_with_transitions.reject { |c| c[:type] == Type::TRANSITION }
      starts = clips.map { |c| c[:frame] }.uniq.sort
      ends = clips.map { |c| c[:frame] + c[:frames] }.uniq.sort
      (starts + ends).uniq.sort
    end
    
    def duration
      self.class.duration(self)
    end
    
    def dynamic_puts(job, input, output, range = nil)
      array = []
      active_clip_identifiers = []
      active_input_ids = []
      active_inputs_by_id = {}
      range ||= TimeRange.new(0, quantize, length)
      frames = segment_frames_dynamic(range)
      frames_count = frames.count
      
      (frames_count - 1).times do |index|
        range.start = frames[index]
        range.length = frames[index + 1] - range.start
        inputs = []
        states = []
        
        # we ignore transitions entirely
        clips_with_transitions = self.class.clips_in_range(self, range)
        clips = clips_with_transitions.reject { |c| c[:type] == Type::TRANSITION }
      
        clip_identifiers = clips.map { |clip| clip.identifier }
        clips_by_identifier = Hash[clip_identifiers.zip(clips)] 
        input_ids = clips.map { |clip| clip.id }.uniq
        inputs_by_id = Hash[input_ids.zip(clips)] 
        
        # add newly appearing inputs
        activating_input_ids = input_ids - active_input_ids
        activating_input_ids.each do |input_id|
          inputs << dynamic_input_from_clip(inputs_by_id[input_id])
        end
        
        # remove disappearing inputs
        deactivating_input_ids = active_input_ids - input_ids
        deactivating_input_ids.each do |input_id|
          states << dynamic_state_remove_clip(active_inputs_by_id[input_id])
        end
        
        active_inputs_by_id = inputs_by_id
        
        clips.each do |clip|
          # state has changed if clip has just appeared
          state_changed = !active_clip_identifiers.include?(clip.identifier)
          next unless state_changed
          scope = dynamic_scope(job, clip, output)
          state = dynamic_state_add_clip(scope, clip, output) 
          states << state
        end

        active_clip_identifiers = clip_identifiers
        active_input_ids = input_ids
      
        array << { inputs: inputs.compact, states: states.compact }
      end
      # deactivate remaining inputs
      states = []
      active_input_ids.each do |input_id|
        states << dynamic_state_remove_clip(active_inputs_by_id[input_id])
      end
      array << { states: states.compact, inputs: [] }
      
      array
    end
    
    def dynamic_scope(job, input, output)
      scope = {}
      scope[:mm_output_path] = job.output_path(output)
      scope[:mm_output] = output
      scope[:mm_fps] = output[:video_rate] || 1

      scope[:mm_dimensions] = output[:dimensions]
      scope[:mm_width], scope[:mm_height] = scope[:mm_dimensions].split 'x'

      # if input[:dimensions]
      #   puts "setting scope overlay dimensions #{input[:dimensions]}"
      #   scope[:overlay_w], scope[:overlay_h] = input[:dimensions].split('x') 
      # end
      scope[:mm_mash] = self
      scope[:mm_in_w] = 'in_w'
      scope[:mm_in_h] = 'in_h'
      scope[:mm_backcolor] = _get(:backcolor)
      
      scope
    end
    
    def dynamic_layer_from_clip(clip, output)
      case clip[:type]
        when Type::VIDEO
          Render::Segment::Layer::LayerRaw::LayerRawVideo.create(clip, output)
        when Type::IMAGE
          Render::Segment::Layer::LayerRaw::LayerRawImage.create(clip, output)
        when Type::THEME
          Render::Segment::Layer::LayerModule::LayerTheme.create(clip, output)
        end
    end
    
    def dynamic_input_type(clip)
      Type::RAW.include?(clip[:type]) ? clip[:type] : Type::CHAIN
    end
    
    def dynamic_input_from_clip(clip)
      # we don't include transitions since they only affect their related clips
      # puts "dynamic_input_from_clip type: #{clip.type}"
      return if clip.type == Type::TRANSITION 
      
      hash = { id: clip.id, type: dynamic_input_type(clip) }
      # hash[:path] = clip[:cached_file] unless hash[:type] == Type::CHAIN
      hash
    end
    
    def dynamic_state_add_clip(scope, clip, output)
      # puts "dynamic_state_add_clip type: #{clip.type}"
      
      hash = { 
        id: clip.id, 
        type: dynamic_input_type(clip), 
        frame: clip[:frame],
        frames: clip[:frames] 
      }
      if AV.includes?(clip[:av], Type::AUDIO)
        hash[:gain] = clip[:gain]
      end
      if AV.includes?(clip[:av], Type::VIDEO)
        layer = dynamic_layer_from_clip(clip, output)
        hash[:filters] = layer.dynamic_filters(scope)
        hash[:overlay] = layer.dynamic_overlay(scope)
        hash[:overlay][:z] = clip[:track]
      end
      hash
    end

    def dynamic_state_remove_clip(clip)
      # we don't include transitions since they only affect their related clips
      return if clip.type == Type::TRANSITION 
      
      { id: clip.id, type: dynamic_input_type(clip), delete: true }
    end
    
    def initialize(hash)
      super
      self.class.init_hash(@hash)
    end

    def preflight(job = nil)
      media.map! do |media|
        case media[:type]
        when Type::VIDEO, Type::AUDIO, Type::IMAGE, Type::FRAME, Type::FONT
          media = Clip.create(media)
          media.preflight(job)
        end
        media
      end
    end
    
    def url_count(desired)
      count = 0
      media.each do |media|
        case media[:type]
        when Type::VIDEO, Type::AUDIO, Type::IMAGE, Type::FONT
          count += 1 if AV.includes?(Asset.av_type(media), desired)
        end
      end
      count
    end


    def audio
      _get(__method__)
    end
    def backcolor
      _get(__method__)
    end
    def length
      _get(__method__)
    end
    def media
      _get(__method__)
    end
    def quantize
      _get(__method__)
    end
    def video
      _get(__method__)
    end
   
  end
end
