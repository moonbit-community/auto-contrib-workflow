///|
/// A compiled glob pattern.
pub struct Glob {
  priv pattern : String
  priv segments : Array[Segment]
}

///|
/// A compiled ordered set of glob patterns.
pub struct GlobSet {
  priv globs : Array[Glob]
}

///|
/// A glob parse or compile failure with byte offsets into the normalized pattern.
pub(all) suberror GlobError {
  /// The pattern is empty.
  EmptyPattern
  /// The pattern contains an empty path segment at the given byte offset.
  EmptySegment(Int)
  /// `**` was used somewhere other than as a complete path segment.
  InvalidRecursiveWildcard(Int)
  /// A character class starting at the given byte offset has no closing `]`.
  UnclosedClass(Int)
  /// A character class starting at the given byte offset contains no entries.
  EmptyClass(Int)
  /// A character class range is descending, such as `z-a`.
  InvalidRange(Int, String)
  /// A pattern at the given set index failed to compile.
  InvalidPattern(Int, String)
} derive(Eq, Debug)

///|
enum Segment {
  Recursive
  Pieces(Array[Piece])
} derive(Eq, Debug)

///|
enum Piece {
  Literal(Byte)
  AnyOne
  AnyMany
  Class(CharClass)
} derive(Eq, Debug)

///|
struct CharClass {
  ranges : Array[ByteRange]
  negated : Bool
} derive(Eq, Debug)

///|
struct ByteRange {
  low : Byte
  high : Byte
} derive(Eq, Debug)

///|
/// Compiles a single glob pattern.
///
/// Supported syntax is intentionally small: `*`, `?`, character classes such as
/// `[abc]`, `[a-z]`, `[!0-9]`, and `**` as a complete path segment.
pub fn compile(pattern : String) -> Glob raise GlobError {
  let normalized = normalized_bytes(pattern)
  if normalized.length() == 0 {
    raise EmptyPattern
  }
  let normalized_pattern = bytes_to_string(normalized)
  let segments : Array[Segment] = []
  let mut start = 0
  let mut index = 0
  while index <= normalized.length() {
    if index == normalized.length() || byte_is(normalized[index], 47) {
      if index == start {
        raise EmptySegment(start)
      }
      segments.push(parse_segment(normalized, start, index))
      start = index + 1
    }
    index += 1
  }
  { pattern: normalized_pattern, segments }
}

///|
/// Compiles an ordered glob set.
///
/// If one pattern fails, `InvalidPattern` reports the zero-based pattern index
/// and a stable diagnostic string for the underlying failure.
pub fn compile_set(patterns : Array[String]) -> GlobSet raise GlobError {
  let globs : Array[Glob] = []
  let mut index = 0
  while index < patterns.length() {
    let result : Result[Glob, GlobError] = try? compile(patterns[index])
    match result {
      Ok(glob) => globs.push(glob)
      Err(error) => raise InvalidPattern(index, describe_error(error))
    }
    index += 1
  }
  { globs, }
}

///|
/// Returns the normalized pattern string used by a compiled glob.
pub fn pattern(glob : Glob) -> String {
  glob.pattern
}

///|
/// Returns true when the compiled glob matches the whole path.
///
/// Both patterns and candidate paths normalize `\` to `/` before matching.
pub fn matches(glob : Glob, path : String) -> Bool {
  let segments = split_path(path)
  match_segments(glob.segments, 0, segments, 0)
}

///|
/// Returns true when any glob in the set matches the whole path.
pub fn matches_any(set : GlobSet, path : String) -> Bool {
  let segments = split_path(path)
  let mut index = 0
  while index < set.globs.length() {
    if match_segments(set.globs[index].segments, 0, segments, 0) {
      return true
    }
    index += 1
  }
  false
}

///|
/// Returns the zero-based IDs of all patterns that match the whole path.
pub fn matched_ids(set : GlobSet, path : String) -> Array[Int] {
  let segments = split_path(path)
  let ids : Array[Int] = []
  let mut index = 0
  while index < set.globs.length() {
    if match_segments(set.globs[index].segments, 0, segments, 0) {
      ids.push(index)
    }
    index += 1
  }
  ids
}

///|
/// Returns a stable, human-readable diagnostic for a glob error.
pub fn describe_error(error : GlobError) -> String {
  match error {
    EmptyPattern => "empty pattern"
    EmptySegment(_) => "empty path segment"
    InvalidRecursiveWildcard(_) => "`**` must be a complete path segment"
    UnclosedClass(_) => "unclosed character class"
    EmptyClass(_) => "empty character class"
    InvalidRange(_, range) => "invalid character class range " + range
    InvalidPattern(_, reason) => reason
  }
}

///|
fn parse_segment(
  pattern : Array[Byte],
  start : Int,
  end : Int,
) -> Segment raise GlobError {
  if end - start == 2 &&
    byte_is(pattern[start], 42) &&
    byte_is(pattern[start + 1], 42) {
    Recursive
  } else {
    let pieces : Array[Piece] = []
    let mut index = start
    while index < end {
      if byte_is(pattern[index], 42) {
        if index + 1 < end && byte_is(pattern[index + 1], 42) {
          raise InvalidRecursiveWildcard(index)
        }
        pieces.push(AnyMany)
        index += 1
      } else if byte_is(pattern[index], 63) {
        pieces.push(AnyOne)
        index += 1
      } else if byte_is(pattern[index], 91) {
        let (class, next) = parse_class(pattern, index, end)
        pieces.push(Class(class))
        index = next
      } else {
        pieces.push(Literal(pattern[index]))
        index += 1
      }
    }
    Pieces(pieces)
  }
}

///|
fn parse_class(
  pattern : Array[Byte],
  start : Int,
  end : Int,
) -> (CharClass, Int) raise GlobError {
  let ranges : Array[ByteRange] = []
  let mut negated = false
  let mut index = start + 1
  if index < end && (byte_is(pattern[index], 33) || byte_is(pattern[index], 94)) {
    negated = true
    index += 1
  }
  while index < end {
    if byte_is(pattern[index], 93) {
      if ranges.length() == 0 {
        raise EmptyClass(start)
      }
      return ({ ranges, negated }, index + 1)
    }
    let low = pattern[index]
    if index + 2 < end &&
      byte_is(pattern[index + 1], 45) &&
      !byte_is(pattern[index + 2], 93) {
      let high = pattern[index + 2]
      if low.to_int() > high.to_int() {
        raise InvalidRange(index, range_text(low, high))
      }
      ranges.push({ low, high })
      index += 3
    } else {
      ranges.push({ low, high: low })
      index += 1
    }
  }
  raise UnclosedClass(start)
}

///|
fn match_segments(
  pattern : Array[Segment],
  pattern_index : Int,
  path : Array[Array[Byte]],
  path_index : Int,
) -> Bool {
  if pattern_index == pattern.length() {
    path_index == path.length()
  } else {
    match pattern[pattern_index] {
      Recursive =>
        if pattern_index + 1 == pattern.length() {
          true
        } else {
          let mut cursor = path_index
          while cursor <= path.length() {
            if match_segments(pattern, pattern_index + 1, path, cursor) {
              return true
            }
            cursor += 1
          }
          false
        }
      Pieces(pieces) =>
        if path_index >= path.length() {
          false
        } else if match_pieces(pieces, 0, path[path_index], 0) {
          match_segments(pattern, pattern_index + 1, path, path_index + 1)
        } else {
          false
        }
    }
  }
}

///|
fn match_pieces(
  pieces : Array[Piece],
  piece_index : Int,
  text : Array[Byte],
  text_index : Int,
) -> Bool {
  if piece_index == pieces.length() {
    text_index == text.length()
  } else {
    match pieces[piece_index] {
      Literal(byte) =>
        text_index < text.length() &&
        text[text_index] == byte &&
        match_pieces(pieces, piece_index + 1, text, text_index + 1)
      AnyOne =>
        text_index < text.length() &&
        match_pieces(pieces, piece_index + 1, text, text_index + 1)
      AnyMany => {
        let mut cursor = text_index
        while cursor <= text.length() {
          if match_pieces(pieces, piece_index + 1, text, cursor) {
            return true
          }
          cursor += 1
        }
        false
      }
      Class(class) =>
        text_index < text.length() &&
        class_matches(class, text[text_index]) &&
        match_pieces(pieces, piece_index + 1, text, text_index + 1)
    }
  }
}

///|
fn class_matches(class : CharClass, byte : Byte) -> Bool {
  let value = byte.to_int()
  let mut matched = false
  let mut index = 0
  while index < class.ranges.length() {
    let range = class.ranges[index]
    if value >= range.low.to_int() && value <= range.high.to_int() {
      matched = true
      break
    }
    index += 1
  }
  if class.negated {
    !matched
  } else {
    matched
  }
}

///|
fn split_path(path : String) -> Array[Array[Byte]] {
  let bytes = normalized_bytes(path)
  let segments : Array[Array[Byte]] = []
  let mut start = 0
  let mut index = 0
  while index <= bytes.length() {
    if index == bytes.length() || byte_is(bytes[index], 47) {
      if index > start {
        segments.push(slice_bytes(bytes, start, index))
      }
      start = index + 1
    }
    index += 1
  }
  segments
}

///|
fn normalized_bytes(input : String) -> Array[Byte] {
  let bytes = @encoding/utf8.encode(input)
  let out : Array[Byte] = []
  for byte in bytes {
    if byte_is(byte, 92) {
      out.push(Int::to_byte(47))
    } else {
      out.push(byte)
    }
  }
  out
}

///|
fn slice_bytes(bytes : Array[Byte], start : Int, end : Int) -> Array[Byte] {
  let out : Array[Byte] = []
  let mut index = start
  while index < end {
    out.push(bytes[index])
    index += 1
  }
  out
}

///|
fn bytes_to_string(bytes : Array[Byte]) -> String {
  @encoding/utf8.decode_lossy(Bytes::from_array(bytes).view())
}

///|
fn range_text(low : Byte, high : Byte) -> String {
  let out = StringBuilder::new()
  out.write_char(Int::unsafe_to_char(low.to_int()))
  out.write_char('-')
  out.write_char(Int::unsafe_to_char(high.to_int()))
  out.to_string()
}

///|
fn byte_is(byte : Byte, value : Int) -> Bool {
  byte.to_int() == value
}
