require_relative 'helpers/spec_helper'

describe File.basename(__FILE__) do
  let(:filter) { MovieMasher::FilterEvaluated.new({ id: 'id' }, {}, {}) }
  context 'scope_value' do
    it 'returns string value when sent invalid expression' do
      value = 'this expression cannot be evaluated'
      scope = {}
      expect(filter.scope_value(scope, value)).to eq value
    end
    it 'returns expression when variables undefined' do
      value = '2 + a * m - j'
      scope = {}
      expect(filter.scope_value(scope, value)).to eq value
    end
    it 'returns result when variables defined' do
      value = '2 + a * m - j'
      scope = { a: 3, m: '5.5', j: -2.5 }
      expect(filter.scope_value(scope, value)).to eq 21
    end
    it 'returns proper nested array for nested non calls' do
      value = '(in_h-mm_max(mm_width, mm_height))-'\
        '((in_h-mm_max(mm_width, mm_height))*mm_t)'
      scope = {}
      scope[:mm_width] = '320'
      scope[:mm_height] = 240
      result = '(in_h-320)-((in_h-320)*mm_t)'
      value = filter.scope_value(scope, value)
      expect(value).to eq result
    end
    it 'returns proper nested array for nested non calls' do
      value = '(in_h-mm_max(512, 288))-((in_h-mm_max(512, 288))*(t/5.5))'
      scope = {}
      result = '(in_h-512)-((in_h-512)*(t/5.5))'
      value = filter.scope_value(scope, value)
      expect(value).to eq result
    end
    it 'returns proper evaluated result for nested calls' do
      value = '(in_h-mm_max(512, 288))-((in_h-mm_max(512, 288))*(t/5.5))'
      scope = { in_h: 1012, t: 11 }
      value = filter.scope_value(scope, value)
      expect(value).to eq(-500)
    end
  end
  context 'command_parameters' do
    it 'returns true for condition, even if types do not match' do
      config = { id: 'id', parameters: [
        name: 'test', value: [{ condition: 'variable < 6', value: '57' }]
      ] }
      condition_filter = MovieMasher::FilterEvaluated.new(config, {}, {})
      scope = { variable: '5' }
      expect(condition_filter.command_parameters(scope)).to eq 'test=57'
    end
  end
end
