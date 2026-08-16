///|
fn hex(value : String) -> String {
  let digits = "0123456789abcdef"
  let builder = StringBuilder()
  for byte in @utf8.encode(value) {
    builder.write_char(digits.get_char((byte.to_int() >> 4) & 0xf).unwrap())
    builder.write_char(digits.get_char(byte.to_int() & 0xf).unwrap())
  }
  builder.to_string()
}

///|
fn lexical_compare(left : String, right : String) -> Int {
  let length = Int::min(left.length(), right.length())
  for index in 0..<length {
    let order = left.unsafe_get(index).compare(right.unsafe_get(index))
    if order != 0 {
      return order
    }
  }
  left.length().compare(right.length())
}

///|
extern "c" fn exit(code : Int) = "exit"

///|
async fn main {
  let bytes = @stdio.stdin.read_all().binary() catch {
      _ => {
        @stdio.stderr.write(@utf8.encode("failed to read fixture\n"))
        exit(2)
        return
      }
    }
  let text = @utf8.decode(bytes) catch {
    _ => {
      @stdio.stderr.write(@utf8.encode("input is not valid UTF-8\n"))
      exit(1)
      return
    }
  }
  let ambient = @environment.EnvTable::from_entries([("KEY11", "ambient")][:])
  let parsed = try @environment.parse_dotenv(text, ambient~) catch {
    error => {
      @stdio.stderr.write(@utf8.encode(error.message() + "\n"))
      exit(1)
      return
    }
  } noraise {
    value => value
  }
  let keys = parsed.keys()
  keys.sort_by(lexical_compare)
  let output = StringBuilder()
  for key in keys {
    output.write_string(key)
    output.write_char('=')
    output.write_string(hex(parsed.get(key).unwrap()))
    output.write_char('\n')
  }
  @stdio.stdout.write(@utf8.encode(output.to_string()))
}
