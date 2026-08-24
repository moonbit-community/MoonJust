///|
pub(all) suberror BuiltinError {
  Unknown(name~ : String)
  Arity(name~ : String, expected~ : String, actual~ : Int)
  Type(name~ : String, expected~ : String, actual~ : @value.Value)
  InvalidPath(value~ : String)
  InvalidRequirement(value~ : String)
  InvalidPattern(value~ : String, detail~ : String)
  Unsupported(name~ : String)
  Failure(message~ : String)
} derive(Eq, Debug)

///|
pub fn BuiltinError::message(self : BuiltinError) -> String {
  match self {
    Unknown(name~) => "unknown builtin `" + name + "`"
    Arity(name~, expected~, actual~) =>
      "builtin `" +
      name +
      "` expects " +
      expected +
      " argument(s), got " +
      actual.to_string()
    Type(name~, expected~, actual~) =>
      "builtin `" + name + "` expects " + expected + ", got " + actual.kind()
    InvalidPath(value~) => "invalid path `" + value + "`"
    InvalidRequirement(value~) => "invalid SemVer requirement `" + value + "`"
    InvalidPattern(detail~, ..) => detail
    Unsupported(name~) =>
      "builtin `" + name + "` is not available on this target"
    Failure(message~) => message
  }
}
