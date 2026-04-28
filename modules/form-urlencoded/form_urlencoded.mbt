///|
/// A decoded `application/x-www-form-urlencoded` key/value pair.
pub(all) struct Pair {
  /// The decoded field name.
  key : String
  /// The decoded field value.
  value : String
} derive(Eq, Debug)

///|
/// Controls how malformed percent escapes and UTF-8 byte sequences are handled.
pub(all) enum ParseMode {
  /// Reject malformed input and return the first structured decode error.
  Strict
  /// Preserve malformed percent escapes and replace malformed UTF-8 bytes.
  Lenient
} derive(Eq, Debug)

///|
/// A strict decode failure with byte offsets into the original input string.
pub(all) suberror DecodeError {
  /// A percent escape at the given byte offset was incomplete or non-hex.
  InvalidPercent(Int, String)
  /// A decoded byte sequence starting at the given input byte offset was not UTF-8.
  InvalidUtf8(Int)
} derive(Eq, Debug)

///|
/// Decodes an `application/x-www-form-urlencoded` string into ordered pairs.
///
/// Empty segments are skipped, duplicate keys are preserved, `+` decodes to a
/// space, and bare keys decode with an empty value.
pub fn decode(
  input : String,
  mode? : ParseMode = Strict,
) -> Array[Pair] raise DecodeError {
  let bytes = @encoding/utf8.encode(input)
  let pairs : Array[Pair] = []
  let mut start = 0
  let mut index = 0
  while index <= bytes.length() {
    if index == bytes.length() || byte_is(bytes[index], 38) {
      if index > start {
        pairs.push(decode_segment(bytes, start, index, mode))
      }
      start = index + 1
    }
    index += 1
  }
  pairs
}

///|
/// Encodes ordered pairs using `application/x-www-form-urlencoded` rules.
///
/// Spaces are written as `+`; other non-safe UTF-8 bytes are percent-encoded.
pub fn encode(pairs : Array[Pair]) -> String {
  let out = StringBuilder::new()
  for index in 0..<pairs.length() {
    if index > 0 {
      out.write_char('&')
    }
    write_encoded_component(out, pairs[index].key)
    out.write_char('=')
    write_encoded_component(out, pairs[index].value)
  }
  out.to_string()
}

///|
/// Encodes one decoded form component using `application/x-www-form-urlencoded`
/// rules.
///
/// Spaces are written as `+`; other non-safe UTF-8 bytes are percent-encoded.
pub fn escape(input : String) -> String {
  let out = StringBuilder::new()
  write_encoded_component(out, input)
  out.to_string()
}

///|
fn decode_segment(
  bytes : Bytes,
  start : Int,
  end : Int,
  mode : ParseMode,
) -> Pair raise DecodeError {
  let mut equals = end
  let mut index = start
  while index < end {
    if byte_is(bytes[index], 61) {
      equals = index
      break
    }
    index += 1
  }
  let key = decode_component(bytes, start, equals, mode)
  if equals == end {
    { key, value: "" }
  } else {
    let value = decode_component(bytes, equals + 1, end, mode)
    { key, value }
  }
}

///|
fn decode_component(
  bytes : Bytes,
  start : Int,
  end : Int,
  mode : ParseMode,
) -> String raise DecodeError {
  let out : Array[Byte] = []
  let offsets : Array[Int] = []
  let mut index = start
  while index < end {
    let byte = bytes[index]
    if byte_is(byte, 43) {
      out.push(Int::to_byte(32))
      offsets.push(index)
      index += 1
    } else if byte_is(byte, 37) {
      if index + 2 >= end {
        match mode {
          Strict => raise InvalidPercent(index, slice_ascii(bytes, index, end))
          Lenient => {
            out.push(byte)
            offsets.push(index)
            index += 1
          }
        }
      } else {
        match (hex_value(bytes[index + 1]), hex_value(bytes[index + 2])) {
          (Some(high), Some(low)) => {
            out.push(Int::to_byte(high * 16 + low))
            offsets.push(index)
            index += 3
          }
          _ =>
            match mode {
              Strict =>
                raise InvalidPercent(
                  index,
                  slice_ascii(bytes, index, index + 3),
                )
              Lenient => {
                out.push(byte)
                offsets.push(index)
                index += 1
              }
            }
        }
      }
    } else {
      out.push(byte)
      offsets.push(index)
      index += 1
    }
  }
  let decoded = Bytes::from_array(out)
  match mode {
    Strict =>
      match first_invalid_utf8(out) {
        Some(offset) => raise InvalidUtf8(offsets[offset])
        None =>
          @encoding/utf8.decode(decoded.view()) catch {
            Malformed(_) => raise InvalidUtf8(start)
          }
      }
    Lenient => @encoding/utf8.decode_lossy(decoded.view())
  }
}

///|
fn first_invalid_utf8(bytes : Array[Byte]) -> Int? {
  let mut index = 0
  while index < bytes.length() {
    let first = bytes[index].to_int()
    if first <= 127 {
      index += 1
    } else if first >= 194 && first <= 223 {
      if index + 1 >= bytes.length() ||
        !is_utf8_continuation(bytes[index + 1].to_int()) {
        return Some(index)
      }
      index += 2
    } else if first == 224 {
      if index + 2 >= bytes.length() ||
        !byte_in_range(bytes[index + 1], 160, 191) ||
        !is_utf8_continuation(bytes[index + 2].to_int()) {
        return Some(index)
      }
      index += 3
    } else if first >= 225 && first <= 236 {
      if index + 2 >= bytes.length() ||
        !is_utf8_continuation(bytes[index + 1].to_int()) ||
        !is_utf8_continuation(bytes[index + 2].to_int()) {
        return Some(index)
      }
      index += 3
    } else if first == 237 {
      if index + 2 >= bytes.length() ||
        !byte_in_range(bytes[index + 1], 128, 159) ||
        !is_utf8_continuation(bytes[index + 2].to_int()) {
        return Some(index)
      }
      index += 3
    } else if first >= 238 && first <= 239 {
      if index + 2 >= bytes.length() ||
        !is_utf8_continuation(bytes[index + 1].to_int()) ||
        !is_utf8_continuation(bytes[index + 2].to_int()) {
        return Some(index)
      }
      index += 3
    } else if first == 240 {
      if index + 3 >= bytes.length() ||
        !byte_in_range(bytes[index + 1], 144, 191) ||
        !is_utf8_continuation(bytes[index + 2].to_int()) ||
        !is_utf8_continuation(bytes[index + 3].to_int()) {
        return Some(index)
      }
      index += 4
    } else if first >= 241 && first <= 243 {
      if index + 3 >= bytes.length() ||
        !is_utf8_continuation(bytes[index + 1].to_int()) ||
        !is_utf8_continuation(bytes[index + 2].to_int()) ||
        !is_utf8_continuation(bytes[index + 3].to_int()) {
        return Some(index)
      }
      index += 4
    } else if first == 244 {
      if index + 3 >= bytes.length() ||
        !byte_in_range(bytes[index + 1], 128, 143) ||
        !is_utf8_continuation(bytes[index + 2].to_int()) ||
        !is_utf8_continuation(bytes[index + 3].to_int()) {
        return Some(index)
      }
      index += 4
    } else {
      return Some(index)
    }
  }
  None
}

///|
fn byte_in_range(byte : Byte, low : Int, high : Int) -> Bool {
  let value = byte.to_int()
  value >= low && value <= high
}

///|
fn is_utf8_continuation(value : Int) -> Bool {
  value >= 128 && value <= 191
}

///|
fn write_encoded_component(out : StringBuilder, input : String) -> Unit {
  let bytes = @encoding/utf8.encode(input)
  for byte in bytes {
    let value = byte.to_int()
    if value == 32 {
      out.write_char('+')
    } else if is_form_safe_byte(value) {
      out.write_char(Int::unsafe_to_char(value))
    } else {
      out.write_char('%')
      out.write_char(hex_digit(value / 16))
      out.write_char(hex_digit(value % 16))
    }
  }
}

///|
fn is_form_safe_byte(value : Int) -> Bool {
  (value >= 48 && value <= 57) ||
  (value >= 65 && value <= 90) ||
  (value >= 97 && value <= 122) ||
  value == 42 ||
  value == 45 ||
  value == 46 ||
  value == 95
}

///|
fn hex_value(byte : Byte) -> Int? {
  let value = byte.to_int()
  if value >= 48 && value <= 57 {
    Some(value - 48)
  } else if value >= 65 && value <= 70 {
    Some(value - 55)
  } else if value >= 97 && value <= 102 {
    Some(value - 87)
  } else {
    None
  }
}

///|
fn hex_digit(value : Int) -> Char {
  if value < 10 {
    Int::unsafe_to_char(48 + value)
  } else {
    Int::unsafe_to_char(55 + value)
  }
}

///|
fn byte_is(byte : Byte, value : Int) -> Bool {
  byte.to_int() == value
}

///|
fn slice_ascii(bytes : Bytes, start : Int, end : Int) -> String {
  let out = StringBuilder::new()
  let mut index = start
  while index < end {
    out.write_char(Int::unsafe_to_char(bytes[index].to_int()))
    index += 1
  }
  out.to_string()
}
