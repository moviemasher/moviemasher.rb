
require_relative 'spec_helper'

describe "Value Parsing..." do
	context "__filter_parse_scope_value" do
		it "returns value when sent just identifier: identifier" do
			value = "identifier"
			scope = Hash.new
			expect(MovieMasher.__filter_parse_scope_value scope, value).to eq value
		end
		it "returns expresions when sent simple expression: 2 + a * m - j" do
			value = "2 + a * m - j"
			scope = Hash.new
			expect(MovieMasher.__filter_parse_scope_value scope, value).to eq '2+a*m-j'
		end
		it "returns proper nested array for nested non calls: (in_h-mm_max(mm_width, mm_height))-((in_h-mm_max(mm_width, mm_height))*mm_t)" do
			value = "(in_h-mm_max(mm_width, mm_height))-((in_h-mm_max(mm_width, mm_height))*mm_t)"
			scope = Hash.new
			scope[:mm_width] = 320
			scope[:mm_height] = 240
			result = "(in_h-320)-((in_h-320)*mm_t)"
			expect(MovieMasher.__filter_parse_scope_value scope, value).to eq result
		end
		it "returns proper nested array for nested non calls: (in_h-mm_max(512, 288))-((in_h-mm_max(512, 288))*(t/5.5))" do
			value = "(in_h-mm_max(512, 288))-((in_h-mm_max(512, 288))*(t/5.5))"
			scope = Hash.new
			result = "(in_h-512)-((in_h-512)*(t/5.5))"
			expect(MovieMasher.__filter_parse_scope_value scope, value).to eq result
		end
	end
#	context "__filter_scope_stack" do
#		it "returns proper hash for simple function call: function(param1, param2)" do
#			value = "function(param1, param2)"
#			hash = {:params=>[{:function=>"function", :params=>["param1", "param2"]}]}
#			expect(MovieMasher.__filter_scope_stack value).to eq hash
#		end
#		it "returns proper nested hash for nested function call: function1(param11, function2(param21, param22))" do
#			value = "function1(param11, function2(param21, param22))"
#			hash = {:params=>[{:function=>"function1", :params=>["param11", {:function=>"function2", :params=>["param21", "param22"]}]}]}
#			expect(MovieMasher.__filter_scope_stack value).to eq hash
#		end
#		it "returns proper string for simple value: value" do
#			value = "value"
#			expect(MovieMasher.__filter_scope_stack value).to eq value
#		end
#		it "returns proper string for simple expression: 2 + a * m - j" do
#			value = "2 + a * m - j"
#			expect(MovieMasher.__filter_scope_stack value).to eq value
#		end
#		it "returns proper hash for tiered non calls: (in_h-out_h)*(t/5.5)" do
#			value = "(in_h-out_h)*(t/5.5)"
#			hash = {:params=>["in_h-out_h"], :append=>[{:prepend=>["*"], :params=>["t/5.5"]}]}
#			expect(MovieMasher.__filter_scope_stack value).to eq hash
#		end
#		it "returns proper hash for tiered non calls: (var1)*((var2)-(var3))" do
#			value = "(var1)*((var2)-(var3))"
#			hash = {:params=>["var1"], :append=>[{:prepend=>["*"], :params=>[{:params=>["var2"], :append=>[{:prepend=>["-"], :params=>["var3"]}]}]}]}
#			expect(MovieMasher.__filter_scope_stack value).to eq hash
#		end
#		it "returns proper hash for nested non calls: (in_h-(8 * 5))*((3 + 2)/5.5)" do
#			value = "(in_h-(8 * 5))*((3 + 2)/5.5)"
#			hash = {:params=>[{:params=>[{:prepend=>["in_h-"], :params=>["8 * 5"]}]}], :append=>[{:prepend=>["*"], :params=>[{:params=>[{:params=>["3 + 2"]}], :append=>["/5.5"]}]}]}
#			expect(MovieMasher.__filter_scope_stack value).to eq hash
#		end
#		it "returns proper hash for expression with parentheses: 2 + (a * m) - j" do
#			value = "2 + (a * m) - j"
#			hash = {:params=>[{:prepend=>["2 +"], :params=>["a * m"]}], :append=>["- j"]}
#			expect(MovieMasher.__filter_scope_stack value).to eq hash
#		end
#		it "returns proper nested hash for nested function call with expression: function1(param11, 1 + function2(param21, param22) - 3)" do
#			value = "function1(param11, 1 + function2(param21, param22) - 3)"
#			hash = {:params=>[{:function=>"function1", :params=>["param11", {:prepend=>["1 +"], :function=>"function2", :params=>["param21", "param22"], :append=>["- 3"]}]}]}
#			expect(MovieMasher.__filter_scope_stack value).to eq hash
#		end
#		it "returns proper nested array for nested function call: function1(param11, function2(param21, param22, param23, param24), function3(param31, param32), param14)" do
#			value = "function1(param11, function2(param21, param22, param23, param24), function3(param31, param32), param14)"
#			hash = {:params=>[{:function=>"function1", :params=>["param11", {:function=>"function2", :params=>["param21", "param22", "param23", "param24"]}, {:function=>"function3", :params=>["param31", "param32"]}, "param14"]}]}
#			expect(MovieMasher.__filter_scope_stack value).to eq hash
#		end
#		it "returns proper nested array for nested non calls: function1(param11, function2(param21, param22, param23, param24), function2(param31, param32), (param14))" do
#			value = "function1(param11, function2(param21, param22, param23, param24), function2(param31, param32), (param14))"
#			hash = {:params=>[{:function=>"function1", :params=>["param11", {:function=>"function2", :params=>["param21", "param22", "param23", "param24"]}, {:function=>"function2", :params=>["param31", "param32"]}, {:params=>["param14"]}]}]}
#			expect(MovieMasher.__filter_scope_stack value).to eq hash
#		end
#		it "returns proper nested array for nested non calls: mm_cmp(mm_input_width, mm_input_height, -1, mm_horz(scale))" do
#			value = "mm_cmp(mm_input_width, mm_input_height, -1, mm_horz(scale))"
#			hash = {:params=>[{:function=>"mm_cmp", :params=>["mm_input_width", "mm_input_height", "-1", {:function=>"mm_horz", :params=>["scale"]}]}]}
#			expect(MovieMasher.__filter_scope_stack value).to eq hash
#		end
#		it "returns proper nested array for nested non calls: mm_cmp(2400, 1800, -1, mm_times(mm_max(512, 288), 1.5))" do
#			value = "mm_cmp(2400, 1800, -1, mm_times(mm_max(512, 288), 1.5))"
#			hash = {:params=>[{:function=>"mm_cmp", :params=>["2400", "1800", "-1", {:function=>"mm_times", :params=>[{:function=>"mm_max", :params=>["512", "288"]}, "1.5"]}]}]}
#			expect(MovieMasher.__filter_scope_stack value).to eq hash
#		end
#	end
#	context "__filter_scope_value_str" do
#	end
#	context "__filter_scope_call" do
#		it "returns properly" do
#			value = "(1 + 3) - 2"
#			scope = Hash.new
#			expect(MovieMasher.__filter_scope_call scope, MovieMasher.__filter_scope_stack(value)).to eq "((1 + 3)- 2)"
#		end
#	end
end


