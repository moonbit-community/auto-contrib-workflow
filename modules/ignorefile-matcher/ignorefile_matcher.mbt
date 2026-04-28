///|
/// One parsed ignore rule.
///
/// `pattern` is normalized to use `/` separators and does not include the
/// leading `!`, leading anchor slash, or trailing directory slash.
pub(all) struct IgnoreRule {
  /// A caller-provided source name such as `.gitignore` or `src/.moonignore`.
  source : String
  /// The 1-based line number in `source`.
  line : Int
  /// The normalized rule pattern.
  pattern : String
  /// The relative directory where this ignore file applies.
  base : String
  /// Whether the rule starts with `!` and re-includes matching paths.
  negated : Bool
  /// Whether the rule ended with `/` and only matches directories or their
  /// descendants.
  directory_only : Bool
  /// Whether the rule was anchored with a leading `/`.
  anchored : Bool
} derive(Eq, Debug)

///|
/// A parsed ignore file.
pub(all) struct IgnoreFile {
  /// A caller-provided source name.
  source : String
  /// The relative directory where this ignore file applies.
  base : String
  /// Parsed rules in source order.
  rules : Array[IgnoreRule]
} derive(Eq, Debug)

///|
/// A matcher built from one or more ignore files.
///
/// Later rules have higher precedence than earlier rules. To model nested
/// ignore files, pass files to `build` from shallowest to deepest.
pub struct IgnoreMatcher {
  /// Rules in precedence order.
  priv rules : Array[IgnoreRule]
} derive(Eq, Debug)

///|
/// The rule that decided a path.
pub(all) struct Explanation {
  /// `true` when the rule ignores the path; `false` when a negated rule
  /// re-includes it.
  ignored : Bool
  /// The matching rule.
  rule : IgnoreRule
} derive(Eq, Debug)

///|
priv struct ClassMatch {
  end : Int
  matched : Bool
}

///|
/// Parses one ignore file.
///
/// Supported syntax is intentionally small: blank lines, comments beginning
/// with `#`, `!` negation, leading `/` anchors, trailing `/` directory rules,
/// `*`, `?`, `**` as a complete path segment, and simple character classes.
pub fn parse(
  text : String,
  source? : String = "",
  base? : String = "",
) -> IgnoreFile {
  let normalized_base = clean_relative_path(base)
  let bytes = @encoding/utf8.encode(text)
  let rules : Array[IgnoreRule] = []
  let mut line_start = 0
  let mut line_number = 1
  let mut index = 0
  while index <= bytes.length() {
    if index == bytes.length() || byte_is(bytes[index], 10) {
      let mut line_end = index
      if line_end > line_start && byte_is(bytes[line_end - 1], 13) {
        line_end -= 1
      }
      match
        parse_line(
          slice_utf8(bytes, line_start, line_end),
          line_number,
          source,
          normalized_base,
        ) {
        Some(rule) => rules.push(rule)
        None => ()
      }
      line_start = index + 1
      line_number += 1
    }
    index += 1
  }
  { source, base: normalized_base, rules }
}

///|
/// Builds a matcher from parsed ignore files.
///
/// Rules from later files override rules from earlier files when they match
/// the same path.
pub fn build(files : Array[IgnoreFile]) -> IgnoreMatcher {
  let rules : Array[IgnoreRule] = []
  for file in files {
    for rule in file.rules {
      rules.push(rule)
    }
  }
  { rules, }
}

///|
/// Parses one ignore file and returns a matcher for it.
pub fn from_text(
  text : String,
  source? : String = "",
  base? : String = "",
) -> IgnoreMatcher {
  build([parse(text, source~, base~)])
}

///|
/// Returns whether `path` is ignored by this matcher.
///
/// Paths are relative to the root used by the caller. Backslashes are treated
/// as path separators. Pass `is_dir=true` when testing a directory path that
/// does not end in `/`.
pub fn IgnoreMatcher::is_ignored(
  self : IgnoreMatcher,
  path : String,
  is_dir? : Bool = false,
) -> Bool {
  match self.explain(path, is_dir~) {
    Some(explanation) => explanation.ignored
    None => false
  }
}

///|
/// Returns the final matching rule for `path`, if any.
pub fn IgnoreMatcher::explain(
  self : IgnoreMatcher,
  path : String,
  is_dir? : Bool = false,
) -> Explanation? {
  let normalized_path = clean_relative_path(path)
  let effective_is_dir = is_dir || has_trailing_separator(path)
  let mut result : Explanation? = None
  for rule in self.rules {
    if rule_matches(rule, normalized_path, effective_is_dir) {
      result = Some({ ignored: !rule.negated, rule })
    }
  }
  result
}

///|
fn parse_line(
  line : String,
  line_number : Int,
  source : String,
  base : String,
) -> IgnoreRule? {
  let trimmed = trim_spaces(line)
  if trimmed == "" {
    return None
  }
  let mut negated = false
  let mut body = trimmed
  if starts_with_bytes(body, "\\#") || starts_with_bytes(body, "\\!") {
    body = slice_text(body, 1, text_byte_length(body))
  } else if starts_with_bytes(body, "#") {
    return None
  } else if starts_with_bytes(body, "!") {
    negated = true
    body = trim_spaces(slice_text(body, 1, text_byte_length(body)))
    if body == "" {
      return None
    }
  }
  let normalized = normalize_slashes(trim_spaces(body))
  let mut start = 0
  let mut end = text_byte_length(normalized)
  let normalized_bytes = @encoding/utf8.encode(normalized)
  let mut anchored = false
  while start < end && byte_is(normalized_bytes[start], 47) {
    anchored = true
    start += 1
  }
  while start + 1 < end &&
        byte_is(normalized_bytes[start], 46) &&
        byte_is(normalized_bytes[start + 1], 47) {
    start += 2
  }
  let mut directory_only = false
  while end > start && byte_is(normalized_bytes[end - 1], 47) {
    directory_only = true
    end -= 1
  }
  if start >= end {
    return None
  }
  let pattern = slice_utf8(normalized_bytes, start, end)
  Some({
    source,
    line: line_number,
    pattern,
    base,
    negated,
    directory_only,
    anchored,
  })
}

///|
fn rule_matches(rule : IgnoreRule, path : String, is_dir : Bool) -> Bool {
  match relative_to_base(path, rule.base) {
    None => false
    Some(relative) => {
      if relative == "" {
        return false
      }
      let candidate = split_path(relative)
      let pattern = split_path(rule.pattern)
      if rule.anchored || has_slash(rule.pattern) {
        path_pattern_matches(pattern, candidate, rule.directory_only, is_dir)
      } else {
        floating_pattern_matches(
          pattern[0],
          candidate,
          rule.directory_only,
          is_dir,
        )
      }
    }
  }
}

///|
fn path_pattern_matches(
  pattern : Array[String],
  candidate : Array[String],
  directory_only : Bool,
  is_dir : Bool,
) -> Bool {
  let mut end = 1
  while end <= candidate.length() {
    if segments_match_range(pattern, 0, candidate, 0, end) {
      if end < candidate.length() {
        return true
      }
      return !directory_only || is_dir
    }
    end += 1
  }
  false
}

///|
fn floating_pattern_matches(
  pattern : String,
  candidate : Array[String],
  directory_only : Bool,
  is_dir : Bool,
) -> Bool {
  let mut index = 0
  while index < candidate.length() {
    if segment_matches(pattern, candidate[index]) {
      if index + 1 < candidate.length() {
        return true
      }
      return !directory_only || is_dir
    }
    index += 1
  }
  false
}

///|
fn segments_match_range(
  pattern : Array[String],
  pattern_index : Int,
  candidate : Array[String],
  candidate_index : Int,
  candidate_end : Int,
) -> Bool {
  if pattern_index == pattern.length() {
    candidate_index == candidate_end
  } else if pattern[pattern_index] == "**" {
    if pattern_index + 1 == pattern.length() {
      true
    } else {
      let mut index = candidate_index
      while index <= candidate_end {
        if segments_match_range(
            pattern,
            pattern_index + 1,
            candidate,
            index,
            candidate_end,
          ) {
          return true
        }
        index += 1
      }
      false
    }
  } else if candidate_index < candidate_end &&
    segment_matches(pattern[pattern_index], candidate[candidate_index]) {
    segments_match_range(
      pattern,
      pattern_index + 1,
      candidate,
      candidate_index + 1,
      candidate_end,
    )
  } else {
    false
  }
}

///|
fn segment_matches(pattern : String, text : String) -> Bool {
  let pattern_bytes = @encoding/utf8.encode(pattern)
  let text_bytes = @encoding/utf8.encode(text)
  segment_matches_from(pattern_bytes, 0, text_bytes, 0)
}

///|
fn segment_matches_from(
  pattern : Bytes,
  pattern_index : Int,
  text : Bytes,
  text_index : Int,
) -> Bool {
  if pattern_index == pattern.length() {
    return text_index == text.length()
  }
  if byte_is(pattern[pattern_index], 42) {
    let mut next = pattern_index + 1
    while next < pattern.length() && byte_is(pattern[next], 42) {
      next += 1
    }
    if next == pattern.length() {
      return true
    }
    let mut index = text_index
    while index <= text.length() {
      if segment_matches_from(pattern, next, text, index) {
        return true
      }
      index += 1
    }
    false
  } else if byte_is(pattern[pattern_index], 63) {
    text_index < text.length() &&
    segment_matches_from(pattern, pattern_index + 1, text, text_index + 1)
  } else if byte_is(pattern[pattern_index], 91) {
    if text_index >= text.length() {
      return false
    }
    match parse_class(pattern, pattern_index, text[text_index]) {
      Some(class_match) =>
        class_match.matched &&
        segment_matches_from(pattern, class_match.end + 1, text, text_index + 1)
      None =>
        byte_is(text[text_index], 91) &&
        segment_matches_from(pattern, pattern_index + 1, text, text_index + 1)
    }
  } else {
    text_index < text.length() &&
    pattern[pattern_index] == text[text_index] &&
    segment_matches_from(pattern, pattern_index + 1, text, text_index + 1)
  }
}

///|
fn parse_class(pattern : Bytes, start : Int, value : Byte) -> ClassMatch? {
  let mut index = start + 1
  if index >= pattern.length() {
    return None
  }
  let mut negated = false
  if byte_is(pattern[index], 33) || byte_is(pattern[index], 94) {
    negated = true
    index += 1
  }
  let mut matched = false
  let mut saw_member = false
  while index < pattern.length() && !byte_is(pattern[index], 93) {
    saw_member = true
    if index + 2 < pattern.length() &&
      byte_is(pattern[index + 1], 45) &&
      !byte_is(pattern[index + 2], 93) {
      let low = pattern[index].to_int()
      let high = pattern[index + 2].to_int()
      let actual = value.to_int()
      if (low <= actual && actual <= high) || (high <= actual && actual <= low) {
        matched = true
      }
      index += 3
    } else {
      if pattern[index] == value {
        matched = true
      }
      index += 1
    }
  }
  if !saw_member || index >= pattern.length() {
    None
  } else if negated {
    Some({ end: index, matched: !matched })
  } else {
    Some({ end: index, matched })
  }
}

///|
fn relative_to_base(path : String, base : String) -> String? {
  if base == "" {
    Some(path)
  } else if path == base {
    Some("")
  } else {
    let prefix = base + "/"
    if starts_with_bytes(path, prefix) {
      Some(slice_text(path, text_byte_length(prefix), text_byte_length(path)))
    } else {
      None
    }
  }
}

///|
fn split_path(path : String) -> Array[String] {
  let segments : Array[String] = []
  let bytes = @encoding/utf8.encode(path)
  let mut start = 0
  let mut index = 0
  while index < bytes.length() {
    if byte_is(bytes[index], 47) {
      segments.push(slice_utf8(bytes, start, index))
      start = index + 1
    }
    index += 1
  }
  segments.push(slice_utf8(bytes, start, bytes.length()))
  segments
}

///|
fn clean_relative_path(path : String) -> String {
  let normalized = normalize_slashes(trim_spaces(path))
  let bytes = @encoding/utf8.encode(normalized)
  let mut start = 0
  let mut end = bytes.length()
  while start + 1 < end &&
        byte_is(bytes[start], 46) &&
        byte_is(bytes[start + 1], 47) {
    start += 2
  }
  while start < end && byte_is(bytes[start], 47) {
    start += 1
  }
  while end > start && byte_is(bytes[end - 1], 47) {
    end -= 1
  }
  slice_utf8(bytes, start, end)
}

///|
fn has_trailing_separator(path : String) -> Bool {
  let bytes = @encoding/utf8.encode(path)
  let mut end = bytes.length()
  while end > 0 && is_space_byte(bytes[end - 1]) {
    end -= 1
  }
  end > 0 && (byte_is(bytes[end - 1], 47) || byte_is(bytes[end - 1], 92))
}

///|
fn has_slash(path : String) -> Bool {
  let bytes = @encoding/utf8.encode(path)
  for byte in bytes {
    if byte_is(byte, 47) {
      return true
    }
  }
  false
}

///|
fn normalize_slashes(input : String) -> String {
  let bytes = @encoding/utf8.encode(input)
  let out : Array[Byte] = []
  for byte in bytes {
    if byte_is(byte, 92) {
      out.push(Int::to_byte(47))
    } else {
      out.push(byte)
    }
  }
  decode_utf8(out)
}

///|
fn trim_spaces(input : String) -> String {
  let bytes = @encoding/utf8.encode(input)
  let mut start = 0
  let mut end = bytes.length()
  while start < end && is_space_byte(bytes[start]) {
    start += 1
  }
  while end > start && is_space_byte(bytes[end - 1]) {
    end -= 1
  }
  slice_utf8(bytes, start, end)
}

///|
fn starts_with_bytes(input : String, prefix : String) -> Bool {
  let input_bytes = @encoding/utf8.encode(input)
  let prefix_bytes = @encoding/utf8.encode(prefix)
  if prefix_bytes.length() > input_bytes.length() {
    return false
  }
  let mut index = 0
  while index < prefix_bytes.length() {
    if input_bytes[index] != prefix_bytes[index] {
      return false
    }
    index += 1
  }
  true
}

///|
fn text_byte_length(input : String) -> Int {
  @encoding/utf8.encode(input).length()
}

///|
fn slice_text(input : String, start : Int, end : Int) -> String {
  slice_utf8(@encoding/utf8.encode(input), start, end)
}

///|
fn slice_utf8(bytes : Bytes, start : Int, end : Int) -> String {
  let out : Array[Byte] = []
  let mut index = start
  while index < end {
    out.push(bytes[index])
    index += 1
  }
  decode_utf8(out)
}

///|
fn decode_utf8(bytes : Array[Byte]) -> String {
  @encoding/utf8.decode_lossy(Bytes::from_array(bytes).view())
}

///|
fn is_space_byte(byte : Byte) -> Bool {
  byte_is(byte, 32) || byte_is(byte, 9) || byte_is(byte, 13)
}

///|
fn byte_is(byte : Byte, value : Int) -> Bool {
  byte.to_int() == value
}
