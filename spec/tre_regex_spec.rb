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

      it 'finds an exact match', :aggregate_failures do
        result = regex.exec('I ate an apple today')

        expect(result).not_to be_nil
        expect(result[:match]).to eq('apple')
        expect(result[:index]).to eq(9)
        expect(result[:end_index]).to eq(14)
        expect(result[:cost]).to eq(0)
      end

      it 'finds a fuzzy match with substitutions', :aggregate_failures do
        # 'aple' has 1 deletion. 'appple' has 1 insertion. 'ipple' has 1 substitution.
        result = regex.exec('I ate an ipple today', max_errors: 1)

        expect(result).not_to be_nil
        expect(result[:match]).to eq('ipple')
        expect(result[:cost]).to eq(1)
        expect(result[:errors][:substitutions]).to eq(1)
      end

      it 'respects granular fuzzy options', :aggregate_failures do
        # We allow 1 error, but 0 substitutions AND 0 deletions. 'ipple' should fail.
        result = regex.exec('I ate an ipple', max_errors: 1, max_substitutions: 0, max_deletions: 0)
        expect(result).to be_nil

        # But a deletion should still work if we allow it
        result2 = regex.exec('I ate an aple', max_errors: 1, max_substitutions: 0)
        expect(result2[:match]).to eq('aple')
        expect(result2[:errors][:deletions]).to eq(1)
      end

      it 'handles massive Unicode characters correctly (byte-to-char index mapping)', :aggregate_failures do
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

      it 'calculates max_err automatically if only granular limits are provided', :aggregate_failures do
        # We only explicitly allow 1 substitution.
        # Under the hood, TRE needs max_err to be bounded, otherwise it defaults to INT_MAX.
        # Our ruby wrapper should automatically set max_err to 1.

        result_success = regex.exec('ipple', max_substitutions: 1)
        expect(result_success).not_to be_nil
        expect(result_success[:match]).to eq('ipple')

        # 'bople' requires 2 substitutions ('a'->'b' and 'p'->'o').
        # Since max_err is bounded to 1, this should successfully fail.
        result_fail = regex.exec('bople', max_substitutions: 1)
        expect(result_fail).to be_nil
      end

      it 'handles searching an empty string gracefully' do
        expect(regex.exec('')).to be_nil
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

      it 'yields multiple exact matches', :aggregate_failures do
        results = []
        regex.match_all('cat, dog, cat') { |m| results << m }

        expect(results.size).to eq(2)
        expect(results[0][:index]).to eq(0)
        expect(results[1][:index]).to eq(10)
      end

      it 'yields multiple fuzzy matches', :aggregate_failures do
        results = regex.match_all('cat, cot, cut', max_errors: 1).to_a

        expect(results.size).to eq(3)
        expect(results[0][:match]).to eq('cat')
        expect(results[1][:match]).to eq('cot')
        expect(results[2][:match]).to eq('cut')
      end
    end

    describe 'Memory Management' do
      it 'handles high volume creation and garbage collection without leaking' do
        expect do
          5_000.times do
            regex = described_class.new('apple|orange|banana')
            regex.exec('I ate an apple')
          end
          GC.start
        end.not_to raise_error
      end

      it 'handles very long input strings without buffer overflow' do
        long_string = 'a' * 1_000_000
        regex = described_class.new('a+')

        result = regex.exec(long_string)
        expect(result[:match].length).to eq(1_000_000)
      end
    end

    describe 'Loop Safety' do
      it 'prevents infinite loops on zero-width matches', :aggregate_failures do
        # The regex 'a*' can match an empty string between characters.
        # Without proper incrementing, match_all would hang here.
        regex = described_class.new('a*')
        results = []

        # Timeout safety to catch infinite loops during the test run
        with_timeout do
          regex.match_all('bb') { |m| results << m }
        end

        # It should find empty matches at index 0, 1, and 2
        expect(results.size).to be >= 3
      end

      it 'correctly advances when matches are adjacent' do
        regex = described_class.new('aa')
        results = regex.match_all('aaaa').to_a

        # Should find 'aa' at index 0 and 'aa' at index 2
        expect(results.map { |r| r[:index] }).to eq([0, 2])
      end
    end

    describe 'Byte-to-Char Cursor Tracking' do
      let(:regex) { described_class.new('apple') }

      it 'advances safely through multi-byte characters without losing sync', :aggregate_failures do
        # '🍎 ' is 2 Ruby chars. 'apple' is 5 chars. ' 🍌 ' is 3 chars.
        text = '🍎 apple 🍌 apple 🍇'

        results = regex.match_all(text).to_a

        expect(results.size).to eq(2)

        # First match should be exactly at character index 2
        expect(results[0][:index]).to eq(2)
        expect(results[0][:end_index]).to eq(7)
        expect(text[results[0][:index]...results[0][:end_index]]).to eq('apple')

        # Second match should be exactly at character index 10
        expect(results[1][:index]).to eq(10)
        expect(results[1][:end_index]).to eq(15)
        expect(text[results[1][:index]...results[1][:end_index]]).to eq('apple')
      end

      it 'strictly adheres to the public API and hides internal byte keys', :aggregate_failures do
        exec_result = regex.exec('apple')
        expect(exec_result.keys).not_to include(:byte_index, :byte_end_index)

        match_all_result = regex.match_all('apple').first
        expect(match_all_result.keys).not_to include(:byte_index, :byte_end_index)
      end
    end

    describe 'Gotchas and Best Practices' do
      describe 'The "Empty Match" Phenomenon' do
        let(:regex) { described_class.new('cat') }

        it 'matches an empty string when max_errors >= pattern length', :aggregate_failures do
          # 3 errors on a 3-letter word mathematically allows matching "" via 3 deletions
          results = regex.match_all('cot, cow', max_errors: 3).to_a

          # The last match should be the empty string
          empty_match = results.find { |r| r[:match] == '' }

          expect(empty_match).not_to be_nil
          expect(empty_match[:cost]).to eq(3)
          expect(empty_match[:errors][:deletions]).to eq(3)
        end

        it 'prevents empty matches when explicitly capping max_deletions', :aggregate_failures do
          # Restrict the engine to a maximum of 2 deletions, preventing it from deleting "cat" entirely
          results = regex.match_all('cot, cow', max_errors: 3, max_deletions: 2).to_a

          empty_match = results.find { |r| r[:match] == '' }

          expect(empty_match).to be_nil
          expect(results.size).to eq(2) # It should only safely match 'cot' and 'cow'
          expect(results.map { |r| r[:match] }).to contain_exactly('cot', 'cow')
        end
      end

      describe 'POSIX vs PCRE Syntax' do
        it 'compiles standard POSIX ERE syntax without error' do
          expect { described_class.new('(cat|dog)s?') }.not_to raise_error
        end

        it 'raises an error for unsupported PCRE syntax like lookaheads' do
          # TRE uses POSIX, which does not support (?=...) lookahead assertions
          expect { described_class.new('cat(?=s)') }.to raise_error(TreRegex::Error)
        end
      end

      describe 'Overlapping Matches in #match_all' do
        it 'consumes the string and does not return overlapping matches by default', :aggregate_failures do
          regex = described_class.new('ana')
          results = regex.match_all('banana').to_a

          # 'banana' contains two 'ana' sequences, but they overlap at the 'a'.
          # Standard behavior should consume the first one and leave 'na', yielding only 1 match.
          expect(results.size).to eq(1)
          expect(results[0][:match]).to eq('ana')
          expect(results[0][:index]).to eq(1)
          expect(results[0][:end_index]).to eq(4)
        end
      end
    end
  end
end
