# TreRegex [![Ruby Checks](https://github.com/le0pard/tre_regex/actions/workflows/main.yml/badge.svg)](https://github.com/le0pard/tre_regex/actions/workflows/main.yml)

`TreRegex` is a robust Ruby gem that provides a high-performance interface to the [TRE](https://github.com/laurikari/tre) approximate regex matching library. Powered by FFI, it allows you to perform lightning-fast fuzzy string searching while safely handling Ruby's Unicode characters.

## Why?

Standard regular expressions are strictly exact. If you are searching text containing typos, OCR errors, or variations in spelling, standard `Regexp` will fail.

While Ruby has built-in string distance metrics (like Levenshtein distance), they usually require comparing whole strings against other whole strings. `TreRegex` solves this by allowing you to search for a pattern *within* a larger body of text while permitting a configurable number of errors (insertions, deletions, and substitutions).

## Features

* **Approximate Matching**: Find matches even if the target string has missing, extra, or substituted characters.
* **Granular Control**: Set strict limits on `max_errors`, or fine-tune by specific error types (`max_insertions`, `max_deletions`, `max_substitutions`).
* **Multi-byte Unicode Safety**: Transparently maps underlying C byte-offsets back to native Ruby character indices (e.g., emojis won't break your offsets).

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
#      :submatches => [],
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
# => {match: "aple", submatches: [], index: 9, end_index: 13, cost: 1, errors: {insertions: 0, deletions: 1, substitutions: 0}}

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
#   {match: "cat", submatches: [], index: 0, end_index: 3, cost: 0, errors: {insertions: 0, deletions: 0, substitutions: 0}},
#  {match: "cot", submatches: [], index: 5, end_index: 8, cost: 1, errors: {insertions: 0, deletions: 0, substitutions: 1}},
#  {match: "cut", submatches: [], index: 10, end_index: 13, cost: 1, errors: {insertions: 0, deletions: 0, substitutions: 1}}
#    ]
```

### Capture Groups (Submatches)

`TreRegex` fully supports standard POSIX capture groups using parentheses `()`. Whenever a match is found, any captured data is returned as an array of strings under the `:submatches` key in the result hash.

If your pattern does not contain any capture groups, `:submatches` will simply return an empty array `[]`.

```ruby
regex = TreRegex::Regex.new('I love (ruby|python)')
result = regex.exec('I love ruby a lot')

# The captured group is extracted exactly as it was matched
result[:submatches] # => ["ruby"]
```

#### Multiple and Optional Groups

You can define multiple capture groups, and they will be returned in the array in the exact order they appear in the pattern.

If you use an optional capture group `?` that does not end up matching anything in the target text, `TreRegex` will safely insert a `nil` in its place in the array to maintain the correct index order.

```ruby
# The first group (cat) is optional. The second group (dog) is required.
regex = TreRegex::Regex.new('(cat)?(dog)')

result = regex.exec('dog')
# => {match: "dog", submatches: [nil, "dog"], index: 0, end_index: 3, cost: 0, errors: {insertions: 0, deletions: 0, substitutions: 0}}
```

#### Fuzzy Capture Groups

One of the most powerful features of `TreRegex` is that capture groups respect your fuzzy matching rules! If a typo occurs *inside* a capture group, the `:submatches` array will return the actual typed text with the typo included.

```ruby
regex = TreRegex::Regex.new('I ate an (apple)')

# We allow 1 error. The user typed 'aple' (1 deletion).
result = regex.exec('I ate an aple', max_errors: 1)

result[:submatches] # => ["aple"]
```

#### The 9-Group Limit

For memory safety and performance during FFI allocation, `TreRegex` allocates a strict maximum of 10 slots per match. Because the first slot is always reserved for the full regex match itself, the engine will only extract a maximum of **9 capture groups** per match.

If your pattern contains 10 or more capture groups `()`, the regex will still compile and match perfectly, but any captured groups beyond the 9th one will be safely ignored and omitted from the `:submatches` array.

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

## Gotchas & Best Practices

### The "Empty Match" Phenomenon

Because `TreRegex` relies on strict mathematical edit distances, you must be careful when setting `max_errors` to a value that is **greater than or equal to the length of your pattern**.

If you allow 3 errors on a 3-letter word, the engine considers *deleting all 3 characters* to be a valid mathematical match (cost = 3). This will result in an unexpected match against an empty string (`""`).

```ruby
regex = TreRegex::Regex.new('cat')

# We allow 3 errors on a 3-letter word.
# The engine matches "cow" (2 substitutions)...
# but it also matches "" at the end of the string (3 deletions)!
regex.match_all('cot, cow', max_errors: 3).to_a
# => [
#     {match: "cot", submatches: [], index: 0, end_index: 3, cost: 1, errors: {insertions: 0, deletions: 0, substitutions: 1}},
#     {match: "cow", submatches: [], index: 5, end_index: 8, cost: 2, errors: {insertions: 0, deletions: 0, substitutions: 2}},
#     {match: "", submatches: [], index: 8, end_index: 8, cost: 3, errors: {insertions: 0, deletions: 3, substitutions: 0}}
#    ]
```

**Best Practice**: if you need a high `max_errors` limit but want to prevent the engine from matching empty strings, explicitly cap the `max_deletions` option so that at least one character of your pattern must survive

```ruby
# Allow 3 total errors, but strictly forbid the engine from deleting more than 2 characters
regex.match_all('cot, cow', max_errors: 3, max_deletions: 2).to_a
# => [
#     {match: "cot", submatches: [], index: 0, end_index: 3, cost: 1, errors: {insertions: 0, deletions: 0, substitutions: 1}},
#     {match: "cow", submatches: [], index: 5, end_index: 8, cost: 2, errors: {insertions: 0, deletions: 0, substitutions: 2}}
#    ] # The empty match is mathematically prevented
```

### POSIX vs. PCRE Syntax

Ruby’s built-in `Regexp` engine uses a PCRE-like syntax (Onigmo), which supports advanced features like lookaheads `(?=...)`, lookbehinds, and backreferences.

The underlying TRE C-library uses **POSIX Extended Regular Expressions (ERE)**. While it supports standard regex features (character classes `[a-z]`, quantifiers `*`, `+`, `?`, and grouping), it **does not** support Perl-specific extensions.

```ruby
# Valid TRE syntax
TreRegex::Regex.new('(cat|dog)s?')

# INVALID: Lookarounds are not supported by POSIX ERE
TreRegex::Regex.new('cat(?=s)') # Failed to compile regex pattern: cat(?=s) (TreRegex::Error)
```

### The Performance Cost of Extreme Fuzziness

Fuzzy matching is inherently more computationally expensive than exact matching. The TRE algorithm scales based on the length of the string and the number of allowed errors.

If you are searching a massive block of text (like a whole book) and set `max_errors: 10`, the engine has to calculate an enormous number of branching possibilities.

**Best Practice**: Keep your error limits tight and realistic. An error limit of 1 to 3 is usually perfect for catching typos. If you need to allow a massive number of errors, consider breaking the target text into smaller chunks (like sentences or words) before matching.

### Unicode Character Indices vs. Byte Offsets

In C, strings are just arrays of bytes. An emoji like 🍎 takes up 4 bytes, which often breaks indexing when C-libraries pass data back to Ruby.

`TreRegex` handles this for you under the hood. The `:index` and `:end_index` returned in the match hash are strictly mapped to **Ruby character indices**, not raw byte offsets.

**Best Practice**: You can safely use the returned indices directly with standard Ruby string slicing, even if the text is filled with emojis or multi-byte characters. Do not use them with `String#byteslice`

```ruby
regex = TreRegex::Regex.new('apple')
target = 'I ate 🍎 and an aple'

result = regex.exec(target, max_errors: 1)
# => {match: "aple", submatches: [], index: 15, end_index: 19, cost: 1, errors: {insertions: 0, deletions: 1, substitutions: 0}}

# This is 100% safe and will correctly return "aple"
target[result[:index]...result[:end_index]]
```

### Overlapping Matches in `match_all`

When using `match_all`, be aware that the engine consumes the string as it matches. By default, standard regex engines (including TRE) do not return overlapping matches.

If you search for `"ana"` in `"banana"`, it will only match the first `"ana"`. Once it consumes those characters, it moves on to the remaining `"na"`.

```ruby
regex = TreRegex::Regex.new('ana')

# Returns 1 match, not 2!
regex.match_all('banana').to_a
# => [{match: "ana", submatches: [], index: 1, end_index: 4, cost: 0, errors: {insertions: 0, deletions: 0, substitutions: 0}}]
```

If you need to find overlapping fuzzy matches, you will need to manually step through the string by advancing your starting index by 1 character after each search.

## Development

Because `TreRegex` compiles the underlying TRE C-library from source, you must have standard C-compilation and `autotools` dependencies installed on your machine before running the setup script

**Ubuntu / Debian Linux**

```bash
sudo apt-get update
sudo apt-get install build-essential autoconf automake libtool gettext autopoint pkg-config
```

**macOS**

Then, install the autotools suite via [Homebrew](https://brew.sh/):
```bash
brew install autoconf automake libtool gettext pkg-config
```

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## License

The gem is available as open source under the terms of the MIT License.
