# TreRegex [![Ruby Checks](https://github.com/le0pard/tre_regex/actions/workflows/main.yml/badge.svg)](https://github.com/le0pard/tre_regex/actions/workflows/main.yml)

`TreRegex` is a robust Ruby gem that provides a high-performance interface to the [TRE](https://github.com/laurikari/tre) approximate regex matching library. Powered by FFI, it allows you to perform lightning-fast fuzzy string searching while safely handling Ruby's Unicode characters.

## Why?

Standard regular expressions are strictly exact. If you are searching text containing typos, OCR errors, or variations in spelling, standard `Regexp` will fail.

While Ruby has built-in string distance metrics (like Levenshtein distance), they usually require comparing whole strings against other whole strings. `TreRegex` solves this by allowing you to search for a pattern *within* a larger body of text while permitting a configurable number of errors (insertions, deletions, and substitutions).

Furthermore, `TreRegex` ships with precompiled cross-platform native binaries. This means users installing your gem do not need a C compiler on their machine—it just works out of the box on Linux, macOS, and Windows.

## Features

* **Approximate Matching**: Find matches even if the target string has missing, extra, or substituted characters.
* **Granular Control**: Set strict limits on `max_errors`, or fine-tune by specific error types (`max_insertions`, `max_deletions`, `max_substitutions`).
* **Multi-byte Unicode Safety**: Transparently maps underlying C byte-offsets back to native Ruby character indices (e.g., emojis won't break your offsets).
* **Memory Safe**: Utilizes Ruby's Garbage Collector to safely manage C-level memory allocation behind the scenes.
* **Precompiled Binaries**: Fast installation with zero compilation required on the end-user's machine.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'tre_regex'
```

And then execute:

```bash
$ bundle install
```

Or install it directly:

```bash
$ gem install tre_regex
```

## Usage

### Basic Matching

Create a new `TreRegex::Regex` object and use `exec` or `test?` to search text

```ruby
require 'tre_regex'

regex = TreRegex::Regex.new('apple', ignore_case: true)

# Simple boolean check
regex.test?('I ate an APPLE today')
# => true

# Get detailed match data
result = regex.exec('I ate an apple today')
# => {
#      :match => "apple",
#      :index => 9,
#      :end_index => 14,
#      :cost => 0,
#      :errors => {:insertions=>0, :deletions=>0, :substitutions=>0}
#    }
```

### Fuzzy Matching

You can configure fuzziness by passing options directly to the `exec` method

```ruby
regex = TreRegex::Regex.new('apple')

# Allow up to 1 error of any kind
regex.exec('I ate an aple', max_errors: 1)
# => {:match=>"aple", :index=>9, :end_index=>13, :cost=>1, :errors=>{:insertions=>0, :deletions=>1, :substitutions=>0}}

# Allow substitutions, but explicitly forbid deletions
regex.exec('I ate an aple', max_substitutions: 1, max_deletions: 0)
# => nil
```

### Finding All Matches

Use `match_all` to find every occurrence of a pattern in a string. It can take a block or return an `Enumerator`

```ruby
regex = TreRegex::Regex.new('cat')

# Returns an array of match hashes
regex.match_all('cat, cot, cut', max_errors: 1).to_a
# => [
#      {:match=>"cat", :index=>0, ...},
#      {:match=>"cot", :index=>5, ...},
#      {:match=>"cut", :index=>10, ...}
#    ]
```

## Configuration Options

`TreRegex` provides fine-grained control over how patterns are compiled and how fuzzy matching constraints are applied.

### Initialization Options

When creating a new `TreRegex::Regex` object, you can pass options to modify how the pattern is compiled:

* **`ignore_case`** *(Boolean)*: If `true`, the regex will match characters regardless of their case (equivalent to the `/i` flag in standard Ruby regex). Default is `false`.

```ruby
# Fails because case doesn't match
exact_regex = TreRegex::Regex.new('ruby')
exact_regex.test?('RUBY') # => false

# Succeeds using the ignore_case flag
case_regex = TreRegex::Regex.new('ruby', ignore_case: true)
case_regex.test?('RUBY') # => true
```

### Fuzzy Matching Options

When calling `exec`, `test?`, or `match_all`, you can pass a hash of fuzzy matching options. If no options are provided, `TreRegex` forces an **exact match** (0 errors allowed).

#### Error Limits

These options strictly limit the number of specific operations required to transform the pattern into the matched string.

* **`max_errors`** *(Integer)*: The total maximum number of combined errors (insertions + deletions + substitutions) allowed for a match.
* **`max_insertions`** *(Integer)*: The maximum number of extra characters allowed in the searched text. *(e.g., Pattern `cat` matching `cart` is 1 insertion)*.
* **`max_deletions`** *(Integer)*: The maximum number of missing characters in the searched text. *(e.g., Pattern `cat` matching `ct` is 1 deletion)*.
* **`max_substitutions`** *(Integer)*: The maximum number of swapped characters. *(e.g., Pattern `cat` matching `cot` is 1 substitution)*.

> **Note:** If you specify granular limits (like `max_deletions: 1`) but omit `max_errors`, the gem will automatically calculate the maximum allowed errors so you don't accidentally trigger an unlimited fuzzy search.

```ruby
regex = TreRegex::Regex.new('banana')

# Allow up to 2 typos of any kind
regex.exec('bananana', max_errors: 2) # => matches "bananana" (2 insertions)
regex.exec('bnnna', max_errors: 2)    # => matches "bnnna" (2 deletions)
regex.exec('bonono', max_errors: 2)   # => matches "bonono" (2 substitutions)

# Another example
regex = TreRegex::Regex.new('library')

# Allow 1 deletion, but STRICTLY 0 substitutions and 0 insertions
regex.exec('librry', max_deletions: 1, max_substitutions: 0, max_insertions: 0)
# => matches "librry"

# This fails because 'lubrary' requires a substitution, which we set to 0
regex.exec('lubrary', max_deletions: 1, max_substitutions: 0, max_insertions: 0)
# => nil
```

#### Cost and Weights

Instead of hard limits, you can assign different "costs" to different types of errors. This is useful if you want to penalize certain typos more heavily than others.

* **`max_cost`** *(Integer)*: The maximum total cost allowed for a match to be considered successful.
* **`weight_insertion`** *(Integer)*: The cost penalty for each inserted character.
* **`weight_deletion`** *(Integer)*: The cost penalty for each deleted character.
* **`weight_substitution`** *(Integer)*: The cost penalty for each substituted character.

```ruby
regex = TreRegex::Regex.new('algorithm')

# We allow a maximum cost of 2.
# Missing/extra characters cost 1 point.
# Wrong characters cost 3 points.
options = {
  max_cost: 2,
  weight_deletion: 1,
  weight_insertion: 1,
  weight_substitution: 3
}

# 'algoritm' has 1 deletion. Cost = 1. (Passes, 1 < 2)
regex.test?('algoritm', options) # => true

# 'algorethm' has 1 substitution. Cost = 3. (Fails, 3 > 2)
regex.test?('algorethm', options) # => false
```


## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## License

The gem is available as open source under the terms of the MIT License.
