///|
pub(all) suberror BuiltinError {
  Unknown(name~ : String)
  Arity(name~ : String, expected~ : String, actual~ : Int)
  Type(name~ : String, expected~ : String, actual~ : String)
  InvalidPath(value~ : String)
  InvalidRequirement(value~ : String)
  InvalidPattern(value~ : String)
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
      "builtin `" + name + "` expects " + expected + ", got " + actual
    InvalidPath(value~) => "invalid path `" + value + "`"
    InvalidRequirement(value~) => "invalid SemVer requirement `" + value + "`"
    InvalidPattern(value~) => "invalid regular expression `" + value + "`"
    Unsupported(name~) =>
      "builtin `" + name + "` is not available on this target"
    Failure(message~) => message
  }
}
