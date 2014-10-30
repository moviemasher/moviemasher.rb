
require_relative 'helpers/spec_helper'

describe File.basename(__FILE__) do
	context "__split" do
		it "('abc{def}ghi{jkl}mnop') == ['abc', 'def', 'ghi', 'jkl', 'mnop']" do
			expect(MovieMasher::Evaluate.send(:__split,'abc{def}ghi{jkl}mnop')).to eq ['abc', 'def', 'ghi', 'jkl', 'mnop']
		end
		it "('{def}ghi{jkl}mnop') == ['', 'def', 'ghi', 'jkl', 'mnop']" do
			expect(MovieMasher::Evaluate.send(:__split,'{def}ghi{jkl}mnop')).to eq ['', 'def', 'ghi', 'jkl', 'mnop']
		end
		it "('abc{def}ghi') == ['abc', 'def', 'ghi']" do
			expect(MovieMasher::Evaluate.send(:__split,'abc{def}ghi')).to eq ['abc', 'def', 'ghi']
		end
		it "('{def}') == ['', 'def']" do
			expect(MovieMasher::Evaluate.send(:__split,'{def}')).to eq ['', 'def']
		end
		it "('abc{def}ghi{jkl}') == ['abc', 'def', 'ghi', 'jkl']" do
			expect(MovieMasher::Evaluate.send(:__split,'abc{def}ghi{jkl}')).to eq ['abc', 'def', 'ghi', 'jkl']
		end
		it "('abc{def}{ghi}jkl') == ['abc', 'def', '', 'ghi', 'jkl']" do
			expect(MovieMasher::Evaluate.send(:__split,'abc{def}{ghi}jkl')).to eq ['abc', 'def', '', 'ghi', 'jkl']
		end
		it "('{def}{ghi}') == ['', 'def', '', 'ghi']" do
			expect(MovieMasher::Evaluate.send(:__split,'{def}{ghi}')).to eq ['', 'def', '', 'ghi']
		end
		it "('abc') == ['abc']" do
			expect(MovieMasher::Evaluate.send(:__split,'abc')).to eq ['abc']
		end
		
	end
end