
require_relative 'helpers/spec_helper'

describe File.basename(__FILE__) do
	let(:filter) { MovieMasher::Filter.new 'id'}
	context "__filter_parse_scope_value" do
		it "returns value when sent just identifier: identifier" do
			value = "identifier"
			scope = Hash.new
			expect(filter.__filter_parse_scope_value scope, value).to eq value
		end
		it "returns expresions when sent simple expression: 2 + a * m - j" do
			value = "2 + a * m - j"
			scope = Hash.new
			expect(filter.__filter_parse_scope_value scope, value).to eq '2+a*m-j'
		end
		it "returns proper nested array for nested non calls: (in_h-mm_max(mm_width, mm_height))-((in_h-mm_max(mm_width, mm_height))*mm_t)" do
			value = "(in_h-mm_max(mm_width, mm_height))-((in_h-mm_max(mm_width, mm_height))*mm_t)"
			scope = Hash.new
			scope[:mm_width] = 320
			scope[:mm_height] = 240
			result = "(in_h-320)-((in_h-320)*mm_t)"
			expect(filter.__filter_parse_scope_value scope, value).to eq result
		end
		it "returns proper nested array for nested non calls: (in_h-mm_max(512, 288))-((in_h-mm_max(512, 288))*(t/5.5))" do
			value = "(in_h-mm_max(512, 288))-((in_h-mm_max(512, 288))*(t/5.5))"
			scope = Hash.new
			result = "(in_h-512)-((in_h-512)*(t/5.5))"
			expect(filter.__filter_parse_scope_value scope, value).to eq result
		end
	end
end


