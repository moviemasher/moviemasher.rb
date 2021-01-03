# frozen_string_literal: true

module MovieMasher
  # A Transfer object and element in Job#callbacks representing a remote
  # request triggered at a particular stage in processing.
  #
  # There are four types of #trigger events for callbacks -
  # Trigger::INITIATE, Trigger::PROGRESS, Trigger::ERROR and
  # Trigger::COMPLETE. After Job#process is called, all
  # Trigger::INITIATE callbacks are requested. Then, every
  # #progress_seconds or so, each Trigger::PROGRESS callback is
  # requested. If a problem is encountered while downloading or
  # rendering/uploading a *required* Output then all TriggereError
  # callbacks are requested. And finally, all Trigger::COMPLETE
  # callbacks are requested.
  #
  # The request body is always a JSON payload built from #data by
  # recursively evaluating all its String values. When a value contains
  # curly brace pairs, the text they wrap is treated as a key path into
  # a scope that contains the Job and Callback being triggered. For
  # instance, {job.destination.type} might evaluate to 'http'. To
  # reference an Array element use a zero-based index in the key path,
  # like {job.inputs.0.type} which might evaluate to 'audio'.
  #
  #   Callback.create {
  #     type: Type::HTTP,
  #     trigger: Trigger::ERROR, # request only if error encountered
  #     host: 'example.com',     # http://example.com/cgi-bin/error.cgi?i=123
  #     path: 'cgi-bin/error.cgi',
  #     parameters: {i: '{job.id}'},   # Scalar - Job#id
  #     data: {                        # body of request, JSON formatted
  #       log: '{job.log}',            # String - Job#log
  #       error: '{job.error}',        # String - Job#error
  #       progress: '{job.progress}'   # Hash - Job#progress
  #     }
  #   }
  class Callback < Transfer
    # Returns a new instance.
    def self.create(hash = nil)
      (hash.is_a?(Callback) ? hash : Callback.new(hash))
    end

    def self.init_hash(hash)
      Hashable._init_key(hash, :trigger, Trigger::COMPLETE)
      if Trigger::PROGRESS == hash[:trigger]
        Hashable._init_key(hash, :progress_seconds, 10)
      end
      Transfer.init_hash(hash)
    end

    def data
      _get(__method__)
    end

    # Hash/Array - Values to recursively evaluate and parse into request body.
    # Default - nil
    def data=(value)
      _set(__method__, value)
    end

    def extension
      _get(__method__)
    end

    # String - Added to file path after #name, with period inserted between.
    def extension=(value)
      _set(__method__, value)
    end

    def name
      _get(__method__)
    end

    # String - The full or basename of file added to URL after #path. If full,
    # #extension will be set and removed from value.
    def name=(value)
      _set(__method__, value)
    end

    def progress_seconds
      _get(__method__)
    end

    # Integer - Seconds to wait before making requests.
    # Default - 44100
    # Triggers - Only Trigger::PROGRESS.
    def progress_seconds=(value)
      _set(__method__, value)
    end

    def trigger
      _get(__method__)
    end

    # String - The event that fires the request.
    # Constant - Trigger::INITIATE, Trigger::PROGRESS, Trigger::ERROR or
    #            Trigger::COMPLETE
    # Default - Trigger::COMPLETE
    def trigger=(value)
      _set(__method__, value)
    end
  end
end
