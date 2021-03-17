require_relative 'helpers/spec_helper'

describe MovieMasher::Evaluate do
  def expect_split(s, *array)
    expect(described_class.send(:__split, s)).to eq array
  end
  context '__split' do
    it "('abc{def}ghi{jkl}mnop') == ['abc', 'def', 'ghi', 'jkl', 'mnop']" do
      expect_split('abc{def}ghi{jkl}mnop', 'abc', 'def', 'ghi', 'jkl', 'mnop')
    end
    it "('{def}ghi{jkl}mnop') == ['', 'def', 'ghi', 'jkl', 'mnop']" do
      expect_split('{def}ghi{jkl}mnop', '', 'def', 'ghi', 'jkl', 'mnop')
    end
    it "('abc{def}ghi') == ['abc', 'def', 'ghi']" do
      expect_split('abc{def}ghi', 'abc', 'def', 'ghi')
    end
    it "('{def}') == ['', 'def']" do
      expect_split('{def}', '', 'def')
    end
    it "('abc{def}ghi{jkl}') == ['abc', 'def', 'ghi', 'jkl']" do
      expect_split('abc{def}ghi{jkl}', 'abc', 'def', 'ghi', 'jkl')
    end
    it "('abc{def}{ghi}jkl') == ['abc', 'def', '', 'ghi', 'jkl']" do
      expect_split('abc{def}{ghi}jkl', 'abc', 'def', '', 'ghi', 'jkl')
    end
    it "('{def}{ghi}') == ['', 'def', '', 'ghi']" do
      expect_split('{def}{ghi}', '', 'def', '', 'ghi')
    end
    it "('abc') == ['abc']" do
      expect_split('abc', 'abc')
    end
  end
end
