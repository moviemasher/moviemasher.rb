
require_relative 'spec_helper'

describe "eval utilities" do
	context "eval_split" do
		it "('abc{def}ghi{jkl}mnop') == ['abc', 'def', 'ghi', 'jkl', 'mnop']" do
			expect(eval_split('abc{def}ghi{jkl}mnop')).to eq ['abc', 'def', 'ghi', 'jkl', 'mnop']
		end
		it "('{def}ghi{jkl}mnop') == ['', 'def', 'ghi', 'jkl', 'mnop']" do
			expect(eval_split('{def}ghi{jkl}mnop')).to eq ['', 'def', 'ghi', 'jkl', 'mnop']
		end
		it "('abc{def}ghi') == ['abc', 'def', 'ghi']" do
			expect(eval_split('abc{def}ghi')).to eq ['abc', 'def', 'ghi']
		end
		it "('{def}') == ['', 'def']" do
			expect(eval_split('{def}')).to eq ['', 'def']
		end
		it "('abc{def}ghi{jkl}') == ['abc', 'def', 'ghi', 'jkl']" do
			expect(eval_split('abc{def}ghi{jkl}')).to eq ['abc', 'def', 'ghi', 'jkl']
		end
		it "('abc{def}{ghi}jkl') == ['abc', 'def', '', 'ghi', 'jkl']" do
			expect(eval_split('abc{def}{ghi}jkl')).to eq ['abc', 'def', '', 'ghi', 'jkl']
		end
		it "('{def}{ghi}') == ['', 'def', '', 'ghi']" do
			expect(eval_split('{def}{ghi}')).to eq ['', 'def', '', 'ghi']
		end
		it "('abc') == ['abc']" do
			expect(eval_split('abc')).to eq ['abc']
		end
		
	end
end