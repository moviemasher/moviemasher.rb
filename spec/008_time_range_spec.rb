require_relative 'helpers/spec_helper'

describe MovieMasher::TimeRange do
  let(:rate) { rand(1..30) }
  let(:short) { rand(1_000) }
  let(:long) { rand(1_000_000) }

  context '#length_seconds' do
    it 'returns supplied length when rate is one' do
      time_range = MovieMasher::TimeRange.new(short, 1, long)
      expect(time_range.length_seconds).to eq long
    end

    it 'returns half supplied length when rate is two' do
      time_range = MovieMasher::TimeRange.new(short, 2, 2 * long)
      expect(time_range.length_seconds).to eq long
    end
  end

  context '#start_seconds' do
    it 'returns supplied start when rate is one' do
      time_range = MovieMasher::TimeRange.new(short, 1, long)
      expect(time_range.start_seconds).to eq short
    end
    it 'returns half supplied start when rate is two' do
      time_range = MovieMasher::TimeRange.new(2 * short, 2, long)
      expect(time_range.start_seconds).to eq short
    end
  end

  context '#equal?' do
    it 'returns true when all times and rate are equal' do
      time_range_1 = MovieMasher::TimeRange.new(short, rate, long)
      time_range_2 = MovieMasher::TimeRange.new(short, rate, long)
      expect(time_range_1).to eq time_range_2 # uses Comparable
      expect(time_range_1 == time_range_2).to be true # uses Comparable
      expect(time_range_1).to_not equal time_range_2 # uses object identity
    end

    it 'returns false when start times unequal' do
      time_range_1 = MovieMasher::TimeRange.new(2, rate, long)
      time_range_2 = MovieMasher::TimeRange.new(4, rate, long)
      expect(time_range_1).to_not eq time_range_2 # uses Comparable
      expect(time_range_1 == time_range_2).to be false # uses Comparable
    end

    it 'returns false when length times unequal' do
      time_range_1 = MovieMasher::TimeRange.new(4, rate, 1)
      time_range_2 = MovieMasher::TimeRange.new(4, rate, 2)
      expect(time_range_1).to_not eq time_range_2 # uses Comparable
      expect(time_range_1 == time_range_2).to be false # uses Comparable
    end

    it 'returns true when different rates express same start and length' do
      time_range_1 = MovieMasher::TimeRange.new(4, 2 * rate, 2)
      time_range_2 = MovieMasher::TimeRange.new(2, rate, 1)
      expect(time_range_1).to eq time_range_2 
    end

    it 'returns false when rates unequal' do
      time_range_1 = MovieMasher::TimeRange.new(2, 2 * rate, 2)
      time_range_2 = MovieMasher::TimeRange.new(2, rate, 2)
      expect(time_range_1).to_not eq time_range_2 
    end
  end

  context '#intersection' do
    it 'returns nil when ranges abut' do
      time_range_1 = MovieMasher::TimeRange.new(0, 10, 4)
      time_range_2 = MovieMasher::TimeRange.new(4, 10, 4)

      expect(time_range_1.intersection(time_range_2)).to be nil
    end

    it 'returns single frame when ranges overlap by one' do
      time_range_1 = MovieMasher::TimeRange.new(0, 10, 4)
      time_range_2 = MovieMasher::TimeRange.new(3, 10, 4)

      expected = MovieMasher::TimeRange.new(3, 10, 1)
      expect(time_range_1.intersection(time_range_2)).to eq expected
    end

    it 'returns shorter range when one contains the other' do
      time_range_1 = MovieMasher::TimeRange.new(0, 10, 10)
      time_range_2 = MovieMasher::TimeRange.new(3, 10, 4)

      expect(time_range_1.intersection(time_range_2)).to eq time_range_2
    end
  end
end
