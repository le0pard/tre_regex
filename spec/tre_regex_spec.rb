# frozen_string_literal: true

RSpec.describe TreRegex do
  it 'has a version number' do
    expect(TreRegex::VERSION).not_to be_nil
  end

  describe TreRegex::Regex do
    describe '#initialize' do
      it 'compiles a valid regular expression' do
        expect { described_class.new('hello') }.not_to raise_error
      end

      it 'raises an error for an invalid regular expression' do
        expect { described_class.new('(invalid') }.to raise_error(TreRegex::Error)
      end

      it 'respects the ignore_case flag' do
        regex = described_class.new('hello', ignore_case: true)
        expect(regex.test?('HELLO')).to be true
      end
    end

    describe '#exec' do
      let(:regex) { described_class.new('apple') }

      it 'returns nil when there is no match' do
        expect(regex.exec('banana')).to be_nil
      end

      it 'finds an exact match' do
        result = regex.exec('I ate an apple today')

        expect(result).not_to be_nil
        expect(result[:match]).to eq('apple')
        expect(result[:index]).to eq(9)
        expect(result[:end_index]).to eq(14)
        expect(result[:cost]).to eq(0)
      end

      it 'finds a fuzzy match with substitutions' do
        # 'aple' has 1 deletion. 'appple' has 1 insertion. 'ipple' has 1 substitution.
        result = regex.exec('I ate an ipple today', max_errors: 1)

        expect(result).not_to be_nil
        expect(result[:match]).to eq('ipple')
        expect(result[:cost]).to eq(1)
        expect(result[:errors][:substitutions]).to eq(1)
      end

      it 'respects granular fuzzy options' do
        # We allow 1 error, but 0 substitutions. 'ipple' should fail.
        result = regex.exec('I ate an ipple', max_errors: 1, max_substitutions: 0)
        expect(result).to be_nil

        # But a deletion should still work
        result2 = regex.exec('I ate an aple', max_errors: 1, max_substitutions: 0)
        expect(result2[:match]).to eq('aple')
        expect(result2[:errors][:deletions]).to eq(1)
      end

      it 'handles massive Unicode characters correctly (byte-to-char index mapping)' do
        # 👨‍👩‍👧‍👦 is 11 bytes in UTF-8, but 1 character in Ruby
        # 🚀 is 4 bytes in UTF-8, but 1 character in Ruby
        unicode_text = '👨‍👩‍👧‍👦 loves 🚀, but hates aple!'

        result = regex.exec(unicode_text, max_errors: 1)

        expect(result).not_to be_nil
        expect(result[:match]).to eq('aple')

        # Test if the Ruby index extraction perfectly matches native Ruby slice
        extracted = unicode_text[result[:index]...result[:end_index]]
        expect(extracted).to eq('aple')
      end
    end

    describe '#test?' do
      let(:regex) { described_class.new('ruby') }

      it 'returns true if a match is found' do
        expect(regex.test?('I love ruby')).to be true
      end

      it 'returns false if no match is found' do
        expect(regex.test?('I love python')).to be false
      end
    end

    describe '#match_all' do
      let(:regex) { described_class.new('cat') }

      it 'returns an enumerator if no block is given' do
        enum = regex.match_all('cat and cot')
        expect(enum).to be_a(Enumerator)
      end

      it 'yields multiple exact matches' do
        results = []
        regex.match_all('cat, dog, cat') { |m| results << m }

        expect(results.size).to eq(2)
        expect(results[0][:index]).to eq(0)
        expect(results[1][:index]).to eq(10)
      end

      it 'yields multiple fuzzy matches' do
        results = regex.match_all('cat, cot, cut', max_errors: 1).to_a

        expect(results.size).to eq(3)
        expect(results[0][:match]).to eq('cat')
        expect(results[1][:match]).to eq('cot')
        expect(results[2][:match]).to eq('cut')
      end
    end
  end
end
