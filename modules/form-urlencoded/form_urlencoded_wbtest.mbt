///|
test "hex value accepts uppercase and lowercase digits" {
  @debug.assert_eq(hex_value(Int::to_byte(48)), Some(0))
  @debug.assert_eq(hex_value(Int::to_byte(57)), Some(9))
  @debug.assert_eq(hex_value(Int::to_byte(65)), Some(10))
  @debug.assert_eq(hex_value(Int::to_byte(70)), Some(15))
  @debug.assert_eq(hex_value(Int::to_byte(97)), Some(10))
  @debug.assert_eq(hex_value(Int::to_byte(102)), Some(15))
  @debug.assert_eq(hex_value(Int::to_byte(103)), None)
}
