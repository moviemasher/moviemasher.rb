# frozen_string_literal: true

module MovieMasher
  # default filter parameters
  module Parameters
    COLOR = [
      { name: 'color', value: 'color' },
      { name: 'size', value: 'mm_dimensions' },
      { name: 'duration', value: 'mm_duration' },
      { name: 'rate', value: 'mm_fps' }
    ].freeze
  end
end
