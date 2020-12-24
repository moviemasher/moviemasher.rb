
require 'shellwords'

module MovieMasher
  # executes commands and optionally checks created files for duration
  module ShellHelper
    def self.audio_command(path)
      if path.to_s.empty? || !File.exist?(path)
        raise(Error::Parameter, "__audio_from_file with invalid path #{path}")
      end
      file_name = File.basename(path, File.extname(path))
      file_name = "#{file_name}-intermediate.#{Intermediate::AUDIO_EXTENSION}"
      out_file = Path.concat(File.dirname(path), file_name)
      switches = []
      switches << switch(path, 'i')
      switches << switch(2, 'ac')
      switches << switch(44_100, 'ar')
      exec_opts = {}
      exec_opts[:command] = switches.join
      exec_opts[:file] = out_file
      exec_opts
    end
    def self.capture(cmd)
      result = Open3.capture3(cmd)
      result = result.reject { |s| s.to_s.empty? }
      result = result.join("\n")
      # puts result
      # make sure result is utf-8 encoded
      enc_options = {}
      enc_options[:invalid] = :replace
      enc_options[:undef] = :replace
      enc_options[:replace] = '?'
      # enc_options[:universal_newline] = true
      result.encode(Encoding::UTF_8, **enc_options)
    end
    def self.command(options)
      out_file = options[:file].to_s
      app = options[:app] || 'ffmpeg'
      app_path = MovieMasher.configuration["#{app}_path".to_sym]
      app_path = app if app_path.to_s.empty?
      cmd = "#{app_path} #{options[:command]}"
      cmd += " #{out_file}" unless out_file.empty?
      cmd
    end
    def self.escape(s)
      Shellwords.escape(s)
    end
    def self.execute(options)
      capture(command(options))
    end
    def self.output_command(output, av_type, duration = nil)
      switches = []
      switches << switch(FloatUtil.string(duration), 't') if duration
      if AV::VIDEO_ONLY == av_type
        switches << switch('', 'an')
      else # we have audio output
        switches << switch(output[:audio_bitrate], 'b:a', 'k')
        switches << switch(output[:audio_rate], 'r:a')
        switches << switch(output[:audio_codec], 'c:a')
      end
      if AV::AUDIO_ONLY == av_type
        switches << switch('', 'vn')
      else # we have visuals
        case output[:type]
        when Type::VIDEO
          switches << switch(output[:dimensions], 's')
          switches << switch(output[:video_format], 'f:v')
          switches << switch(output[:video_codec], 'c:v')
          switches << switch(output[:video_bitrate], 'b:v', 'k')
          switches << switch(output[:video_rate], 'r:v')
        when Type::IMAGE
          switches << switch(output[:quality], 'q:v')
          switches << switch('1', 'vframes')
          # switches << switch('debug', 'v')
          unless output[:offset].to_s.empty?
            output_time = TimeRange.input_time(output, :offset)
            switches << switch(output_time, 'ss')
          end
#           switches << switch('1', 'updatefirst')
        when Type::SEQUENCE
          switches << switch(output[:quality], 'q:v')
          switches << switch(output[:video_rate], 'r:v')
        end
      end
      switches << switch(output[:metadata], 'metadata')
      switches.join
    end
    def self.raise_unless_rendered(result, cmd, options)
      logs = []
      out_file = options[:file].to_s
      outputs = !['', '/dev/null'].include?(out_file)
      dur = options[:duration]
      precision = options[:precision] || 1
      logs += __raise_if_no_file(out_file, cmd, result) if outputs
      if dur
        logs += __raise_unless_duration(result, dur, precision, out_file, cmd)
      end
      logs
    end
    def self.set_output_commands(job, output)
      output[:commands] = []
      switches = end_switches = ''
      audio_dur = video_dur = FloatUtil::ZERO
      rend_path, out_path = __job_paths(job, output)
      avb, v_graphs, a_graphs = __output_graphs(output, job)
      output_type = output[:type]
      a_or_v = Type::RAW_AVS.include?(output_type)
      unless AV::AUDIO_ONLY == avb
        if 1 == v_graphs.length
          graph = v_graphs.first
          video_dur = graph.duration
          switches += __graph_command(graph, output)
        else
          ffconcat = 'ffconcat version 1.0'
          v_graphs.length.times do |index|
            graph = v_graphs[index]
            duration = graph.duration
            video_dur += duration
            out_file_name = "concat-#{index}.#{output[:extension]}"
            out_file = "#{out_path}#{out_file_name}"
            ffconcat += "\nfile '#{out_file_name}'\nduration #{duration}"
            output[:commands] << {
              duration: duration,
              file: out_file, precision: output[:precision],
              command: '-y' + __graph_command(graph, output) \
                + output_command(output, AV::VIDEO_ONLY, duration) \
                + switch('0', 'qp')
            }
          end
          file_path = "#{out_path}concat.txt"
          output[:commands] << { content: ffconcat, file: file_path }
          switches += switch("'#{file_path}'", 'i')
          end_switches += switch('copy', 'c:v')
        end
      end
      unless AV::VIDEO_ONLY == avb
        if __audio_raw(a_graphs)
          # just one non-looping graph, starting at zero with no gain change
          graph = a_graphs.first
          audio_dur = graph[:length]
          cmd_hash = audio_command(graph[:cached_file])
          output[:commands] << cmd_hash
          graph[:waved_file] = cmd_hash[:file]
        else
          # merge audio and feed resulting file to ffmpeg
          audio_cmd = ''
          a_len = a_graphs.length
          a_len.times do |index|
            graph = a_graphs[index]
            __raise_if_negative(graph[:start], "negative start time #{graph}")
            __raise_if_zero(graph[:length], "zero length #{graph}")
            audio_dur = FloatUtil.max(audio_dur, graph[:start] + graph[:length])
            cmd_hash = audio_command(graph[:cached_file])
            output[:commands] << cmd_hash
            graph[:waved_file] = cmd_hash[:file]
            audio_cmd += __audio_graph(graph, index)
          end
          max_dur = FloatUtil.max(audio_dur, video_dur)
          audio_cmd += __audio_silence(a_len, max_dur)
          path = __audio_path(out_path, audio_cmd)
          output[:commands] << {
            app: 'ecasound', command: audio_cmd, precision: output[:precision],
            file: path, duration: max_dur
          }
          graph = {
            type: Type::AUDIO, offset: FloatUtil::ZERO, length: audio_dur,
            waved_file: path
          }
        end
        # audio graph now represents just one file
        if Type::WAVEFORM == output_type
          output[:commands] << {
            app: 'audiowaveform', file: rend_path,
            command: __waveform_switches(graph, output)
          }
        else
          switches += switch(graph[:waved_file], 'i')
          end_switches += __audio_switches(graph, audio_dur)
        end
      end
      unless switches.empty?
        # we've got audio and/or video
        max_dur = FloatUtil.max(audio_dur, video_dur)
        output[:commands] << {
          file: rend_path, precision: output[:precision],
          pass: __is_two_pass(a_or_v, v_graphs),
          duration: __type_duration(output_type, max_dur),
          command: '-y ' + (switches + end_switches) \
            + output_command(output, avb, __output_duration(a_or_v, max_dur))
        }
      end
    end
    def self.switch(value, prefix = '', suffix = '', dont_escape = false)
      cmd = ''
      if value
        value = value.to_s.strip
        unless dont_escape
          splits = Shellwords.split(value)
          splits = splits.map { |word| escape(word) }
          # puts "SPLITS: #{splits}" if 1 < splits.length
          value = splits.join(' ')
        end
        cmd += ' ' # always add a leading space
        if value.start_with?('-') # it's a switch, just include and ignore rest
          cmd += value
        else # prepend value with prefix and space
          cmd += '-' unless prefix.start_with?('-')
          cmd += prefix
          cmd += ' ' + value unless value.empty?
          cmd += suffix unless cmd.end_with?(suffix) # note lack of space!
        end
      end
      cmd
    end
    def self.switch_unescaped(value, prefix = '', suffix = '')
      switch(value, prefix, suffix, true)
    end
    def self.__atrim(offset, dur)
      offset = ShellHelper.escape(offset)
      dur = ShellHelper.escape(dur)
      "'[0:a]atrim=start=#{offset}:duration=#{dur},asetpts=expr=PTS-STARTPTS'"
    end
    def self.__audio_gains(volume, graph)
      start = graph[:start]
      length = graph[:length]
      loops = graph[:loop] || 1
      audio_cmd = ''
      if Mash.gain_changes(volume)
        volume = volume.to_s unless volume.is_a?(String)
        volume = "0,#{volume},1,#{volume}" unless volume.include?(',')
        volume = volume.split(',')
        z = volume.length / 2
        audio_cmd += " -ea:0 -klg:1,0,100,#{z}"
        z.times do |i|
          p = (i + 1) * 2
          pos = volume[p - 2].to_f
          val = volume[p - 1].to_f
          if FloatUtil.gtr(pos, FloatUtil::ZERO)
            pos = (length * loops.to_f * pos)
          end
          audio_cmd += ",#{FloatUtil.precision(start + pos)},#{val}"
        end
      end
      audio_cmd
    end
    def self.__audio_graph(graph, counter)
      audio_cmd = ''
      loops = graph[:loop] || 1
      volume = graph[:gain]
      audio_cmd += " -a:#{counter + 1} -i "
      audio_cmd += 'audioloop,' if 1 < loops
      audio_cmd += "playat,#{graph[:start]},"
      audio_cmd += "select,#{graph[:offset]}"
      audio_cmd += ",#{graph[:length]},#{graph[:waved_file]}"
      audio_cmd += __audio_loops(loops, graph[:length])
      audio_cmd += __audio_gains(volume, graph)
      audio_cmd
    end
    def self.__audio_loops(loops, length)
      (1 < loops ? " -t:#{FloatUtil.string(length)}" : '')
    end
    def self.__audio_path(out_path, audio_cmd)
      hex = Digest::SHA2.new(256).hexdigest(audio_cmd)
      "#{out_path}audio-#{hex}.#{Intermediate::AUDIO_EXTENSION}"
    end
    def self.__audio_raw(graphs)
      graph = graphs.first
      __raise_if_negative(graph[:start], "negative start time #{graph}")
      __raise_if_zero(graph[:length], "zero length #{graph}")
      raw = (1 == graphs.length)
      raw &&= graph[:loop].nil? || (1 == graph[:loop])
      raw &&= !Mash.gain_changes(graph[:gain])
      raw &&= FloatUtil.cmp(graph[:start], FloatUtil::ZERO)
      raw
    end
    def self.__audio_silence(c, dur)
      " -a:#{c + 1} -i playat,0,tone,sine,0,#{dur} -a:all -z:mixmode,sum -o "
    end
    def self.__audio_switches(graph, audio_dur)
      switches = []
      trim_not_needed = FloatUtil.cmp(graph[:offset], FloatUtil::ZERO)
      trim_not_needed &&= FloatUtil.cmp(graph[:length], graph[:duration])
      unless trim_not_needed
        switches << switch(__atrim(graph[:offset], audio_dur), 'af')
      end
      switches << switch(1, 'async')
      switches.join
    end
    def self.__graph_command(graph, output)
      cmds = []
      inputs = graph.inputs
      cmd = graph.graph_command(output)
      __raise_if_empty(cmd, "could not build graph command #{graph}")
      inputs.each { |i| i.each { |k, v| cmds << switch(v, k.to_s) } }
      unless '[0:v]' == cmd
        cmds << switch_unescaped(%("#{cmd}"), 'filter_complex')
      end
      if output[:pixel_format] && cmd.include?('format=pix_fmts=')
        cmds << switch(output[:pixel_format], 'pix_fmt')
      end
      cmds.join
    end
    def self.__is_two_pass(a_or_v, v_graphs)
      a_or_v && v_graphs.length < 2
    end
    def self.__job_paths(job, output)
      [job.render_path(output), job.output_path(output)]
    end
    def self.__output_duration(a_or_v, max_dur)
      (a_or_v ? max_dur : nil)
    end
    def self.__output_graphs(output, job)
      v_graphs = []
      a_graphs = []
      avb = output[:av]
      unless AV::AUDIO_ONLY == avb
        v_graphs = job.video_graphs
        avb = AV::AUDIO_ONLY if v_graphs.empty?
      end
      unless AV::VIDEO_ONLY == avb
        a_graphs = job.audio_graphs
        avb = AV::VIDEO_ONLY if a_graphs.empty?
      end
      [avb, v_graphs, a_graphs]
    end
    def self.__raise_if_empty(s, msg)
      raise(Error::JobInput, msg) if s.empty?
    end
    def self.__raise_if_negative(f, msg)
      raise(Error::JobInput, msg) unless FloatUtil.gtre(f, FloatUtil::ZERO)
    end
    def self.__raise_if_no_file(path, cmd, result)
      logs = []
      if path.include?('%')
        file_count = Dir["#{File.dirname(path)}/"].count
        msg = "created #{file_count} file#{1 == file_count ? '' : 's'}\n#{cmd}"
        raise(Error::JobRender.new(result, msg)) if file_count.zero?
        logs << { info: (proc { msg }) }
      elsif File.exist?(path)
        size = File.size?(path).to_i
        if size.zero?
          raise(Error::JobRender.new(result, "couldn't create #{path}\n#{cmd}"))
        else
          logs << { info: (proc { "created #{size} byte file #{path}" }) }
        end
      else
        raise(Error::JobRender.new(result, "couldn't create #{path}\n#{cmd}"))
      end
      logs
    end
    def self.__raise_if_zero(f, msg)
      raise(Error::JobInput, msg) unless FloatUtil.gtr(f, FloatUtil::ZERO)
    end
    def self.__raise_unless_duration(result, duration, precision, out_file, cmd)
      logs = []
      has_no_video = Info.get(out_file, Info::DIMENSIONS).to_s.empty?
      dur_key = (has_no_video ? Info::AUDIO_DURATION : Info::VIDEO_DURATION)
      test_duration = Info.get(out_file, dur_key).to_f
      msg = "rendered with duration: #{test_duration} #{out_file}"
      logs << { debug: (proc { msg }) }
      if test_duration.zero?
        msg = "failed to see if #{duration} == duration of #{out_file}\n#{cmd}"
        raise(Error::JobRender.new(result, msg))
      end
      ok = FloatUtil.cmp(duration, test_duration, precision.abs)
      unless ok
        logs << { warn: (proc { result }) }
        if -1 < precision
          msg = "expected #{has_no_video ? 'audio' : 'video'} duration of "\
            "#{duration} but found #{test_duration} in #{out_file}\n#{cmd}"
          raise(Error::JobRender.new(result, msg))
        end
        logs << { warn: (proc { msg }) }
      end
      logs
    end
    def self.__type_duration(type, max_dur)
      (Type::IMAGES.include?(type) ? nil : max_dur)
    end
    def self.__waveform_switches(graph, output)
      switches = []
      dimensions = output[:dimensions].split 'x'
      duration = graph[:duration]
      pixels_per_second = (dimensions.first.to_f / graph[:duration]).to_i

      puts "pixels_per_second: #{pixels_per_second}"
      switches << switch(graph[:waved_file], '--input-filename')
      switches << switch(dimensions.first, '--width')
      switches << switch(dimensions.last, '--height')
      switches << switch(pixels_per_second, '--pixels-per-second')
      switches << switch(output[:forecolor], '--waveform-color')
      switches << switch(output[:backcolor], '--background-color')
      switches << switch('', '--no-axis-labels')
      switches << switch('', '--output-filename')
      switches.join
    end
  end
end
