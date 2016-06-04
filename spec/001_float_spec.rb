
require_relative 'helpers/spec_helper'

describe File.basename(__FILE__) do
  context 'MovieMasher::FloatUtil.cmp' do
    it '(1.000001, 1.00001, 3) == true' do
      expect(MovieMasher::FloatUtil.cmp(1.000001, 1.00001, 3)).to be_truthy
    end
    it '(1.001, 1.0001, 4) == false' do
      expect(MovieMasher::FloatUtil.cmp(1.001, 1.0001, 4)).to be_falsey
    end
    it '(60.49, 60.24, 0) == true' do
      expect(MovieMasher::FloatUtil.cmp(60.49, 60.24, 0)).to be_truthy
    end
    it '(9.49, 9.56, 0) == false' do
      expect(MovieMasher::FloatUtil.cmp(9.49, 9.56, 0)).to be_falsey
    end
    it '(60.49, 60.51, 1) == true' do
      expect(MovieMasher::FloatUtil.cmp(60.49, 60.51, 1)).to be_truthy
    end
    it '(60.44, 60.51, 1) == false' do
      expect(MovieMasher::FloatUtil.cmp(60.44, 60.51, 1)).to be_falsey
    end
  end
  context 'MovieMasher::FloatUtil.gtr' do
    it '(1.000001, 1.00001, 3) == false' do
      expect(MovieMasher::FloatUtil.gtr(1.000001, 1.00001, 3)).to be_falsey
    end
    it '(1.001, 1.0001, 4) == true' do
      expect(MovieMasher::FloatUtil.gtr(1.001, 1.0001, 4)).to be_truthy
    end
  end
  context 'MovieMasher::FloatUtil.gtre' do
    it '(1.000001, 1.00001, 3) == false' do
      expect(MovieMasher::FloatUtil.gtr(1.000001, 1.00001, 3)).to be_falsey
    end
    it '(1.001, 1.001, 3) == true' do
      expect(MovieMasher::FloatUtil.gtr(1.001, 1.0001, 4)).to be_truthy
    end
  end
end
