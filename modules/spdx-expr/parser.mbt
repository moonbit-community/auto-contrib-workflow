///|
/// A structured parse error with a byte offset into the input expression.
pub(all) suberror ParseError {
  /// An expression was expected at the given byte offset.
  ExpectedExpression(Int)
  /// A license or exception identifier was expected at the given byte offset.
  ExpectedIdentifier(Int)
  /// A parenthesized expression was not closed. The offset points to `(`.
  UnclosedParen(Int)
  /// `WITH` was applied to something other than a single license identifier.
  InvalidWithTarget(Int)
  /// Extra or invalid input remained at the given byte offset.
  UnexpectedToken(Int, String)
} derive(Eq, Debug)

///|
priv struct Parser {
  bytes : Bytes
  mut pos : Int
}

///|
fn Parser::new(input : String) -> Parser {
  { bytes: @encoding/utf8.encode(input), pos: 0 }
}

///|
/// Parses an SPDX license expression.
///
/// Supported operators are `WITH`, `AND`, and `OR`; `WITH` binds tighter than
/// `AND`, and `AND` binds tighter than `OR`.
pub fn parse(input : String) -> Expr raise ParseError {
  let parser = Parser::new(input)
  let expr = parser.parse_or()
  parser.skip_ws()
  if parser.at_end() {
    expr
  } else {
    raise UnexpectedToken(parser.pos, parser.peek_token_text())
  }
}

///|
fn Parser::parse_or(self : Parser) -> Expr raise ParseError {
  let mut expr = self.parse_and()
  while self.consume_keyword("OR") {
    let right = self.parse_and()
    expr = Or(expr, right)
  }
  expr
}

///|
fn Parser::parse_and(self : Parser) -> Expr raise ParseError {
  let mut expr = self.parse_with()
  while self.consume_keyword("AND") {
    let right = self.parse_with()
    expr = And(expr, right)
  }
  expr
}

///|
fn Parser::parse_with(self : Parser) -> Expr raise ParseError {
  let primary = self.parse_primary()
  let with_pos = self.position_after_ws()
  if self.consume_keyword("WITH") {
    match primary {
      License(license_id) => {
        self.skip_ws()
        let exception_pos = self.pos
        let exception_id = self.parse_identifier()
        if is_operator_keyword(exception_id) {
          raise ExpectedIdentifier(exception_pos)
        }
        With(license_id, exception_id)
      }
      _ => raise InvalidWithTarget(with_pos)
    }
  } else {
    primary
  }
}

///|
fn Parser::parse_primary(self : Parser) -> Expr raise ParseError {
  self.skip_ws()
  if self.at_end() {
    raise ExpectedExpression(self.pos)
  }
  if self.consume_raw_byte(40) {
    let open_pos = self.pos - 1
    let expr = self.parse_or()
    self.skip_ws()
    if self.consume_raw_byte(41) {
      expr
    } else {
      raise UnclosedParen(open_pos)
    }
  } else {
    let id_pos = self.pos
    let license_id = self.parse_identifier()
    if is_operator_keyword(license_id) {
      raise ExpectedExpression(id_pos)
    }
    License(license_id)
  }
}

///|
fn Parser::parse_identifier(self : Parser) -> String raise ParseError {
  self.skip_ws()
  let start = self.pos
  if self.at_end() || !is_identifier_start(self.bytes[self.pos]) {
    raise ExpectedIdentifier(start)
  }
  self.pos += 1
  while self.pos < self.bytes.length() &&
        is_identifier_continue(self.bytes[self.pos]) {
    self.pos += 1
  }
  slice_ascii(self.bytes, start, self.pos)
}

///|
fn Parser::consume_keyword(self : Parser, word : String) -> Bool {
  self.skip_ws()
  let expected = @encoding/utf8.encode(word)
  if self.pos + expected.length() > self.bytes.length() {
    false
  } else {
    let mut index = 0
    let mut matches = true
    while index < expected.length() {
      if self.bytes[self.pos + index].to_int() != expected[index].to_int() {
        matches = false
      }
      index += 1
    }
    let end = self.pos + expected.length()
    if matches && self.keyword_boundary(end) {
      self.pos = end
      true
    } else {
      false
    }
  }
}

///|
fn Parser::consume_raw_byte(self : Parser, value : Int) -> Bool {
  if self.pos < self.bytes.length() && byte_is(self.bytes[self.pos], value) {
    self.pos += 1
    true
  } else {
    false
  }
}

///|
fn Parser::skip_ws(self : Parser) -> Unit {
  while self.pos < self.bytes.length() && is_ws(self.bytes[self.pos]) {
    self.pos += 1
  }
}

///|
fn Parser::position_after_ws(self : Parser) -> Int {
  let mut pos = self.pos
  while pos < self.bytes.length() && is_ws(self.bytes[pos]) {
    pos += 1
  }
  pos
}

///|
fn Parser::at_end(self : Parser) -> Bool {
  self.pos >= self.bytes.length()
}

///|
fn Parser::keyword_boundary(self : Parser, end : Int) -> Bool {
  end >= self.bytes.length() || !is_identifier_continue(self.bytes[end])
}

///|
fn Parser::peek_token_text(self : Parser) -> String {
  let start = self.position_after_ws()
  let first = self.bytes[start]
  if byte_is(first, 40) || byte_is(first, 41) {
    slice_ascii(self.bytes, start, start + 1)
  } else {
    let mut end = start
    while end < self.bytes.length() &&
          !is_ws(self.bytes[end]) &&
          !byte_is(self.bytes[end], 40) &&
          !byte_is(self.bytes[end], 41) {
      end += 1
    }
    slice_ascii(self.bytes, start, end)
  }
}

///|
fn is_operator_keyword(value : String) -> Bool {
  value == "AND" || value == "OR" || value == "WITH"
}

///|
fn is_identifier_start(byte : Byte) -> Bool {
  is_ascii_alpha(byte) || is_ascii_digit(byte)
}

///|
fn is_identifier_continue(byte : Byte) -> Bool {
  is_identifier_start(byte) ||
  byte_is(byte, 45) ||
  byte_is(byte, 46) ||
  byte_is(byte, 43)
}

///|
fn is_ascii_alpha(byte : Byte) -> Bool {
  byte_in_range(byte, 65, 90) || byte_in_range(byte, 97, 122)
}

///|
fn is_ascii_digit(byte : Byte) -> Bool {
  byte_in_range(byte, 48, 57)
}

///|
fn is_ws(byte : Byte) -> Bool {
  byte_is(byte, 32) ||
  byte_is(byte, 9) ||
  byte_is(byte, 10) ||
  byte_is(byte, 13)
}

///|
fn byte_in_range(byte : Byte, low : Int, high : Int) -> Bool {
  let value = byte.to_int()
  value >= low && value <= high
}

///|
fn byte_is(byte : Byte, value : Int) -> Bool {
  byte.to_int() == value
}

///|
fn slice_ascii(bytes : Bytes, start : Int, end : Int) -> String {
  let out = StringBuilder::new()
  for index in start..<end {
    out.write_char(Int::unsafe_to_char(bytes[index].to_int()))
  }
  out.to_string()
}
