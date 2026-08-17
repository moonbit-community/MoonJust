///|
/// Runtime values produced by MoonJust expressions.
pub(all) enum Value {
  String(String)
  List(Array[Value])
  Bool(Bool)
} derive(Eq, Debug)

///|
pub fn Value::as_string(self : Value) -> String? {
  match self {
    String(value) => Some(value)
    List([String(value)]) => Some(value)
    List([Bool(true)]) => Some("true")
    List(_) | Bool(false) => None
    Bool(true) => Some("true")
  }
}

///|
pub fn Value::as_list(self : Value) -> ArrayView[Value]? {
  match self {
    List(value) => Some(value[:])
    String(_) | Bool(_) => None
  }
}

///|
pub fn Value::as_bool(self : Value) -> Bool? {
  match self {
    Bool(value) => Some(value)
    String(_) | List(_) => None
  }
}

///|
pub fn Value::truthy(self : Value) -> Bool {
  match self {
    Bool(value) => value
    String(_) => true
    List(_) => !self.elements().is_empty()
  }
}

///|
/// Return the upstream-compatible string elements represented by this value.
pub fn Value::elements(self : Value) -> Array[String] {
  match self {
    String(value) => [value]
    Bool(true) => ["true"]
    Bool(false) => []
    List(values) => {
      let result : Array[String] = []
      for value in values {
        result.append(value.elements())
      }
      result
    }
  }
}

///|
/// Join a value for interpolation, environment variables, and recipe argv.
pub fn Value::to_string(self : Value) -> String {
  self.elements().join(" ")
}

///|
fn quote_element(value : String) -> String {
  let builder = StringBuilder()
  builder.write_char('"')
  for character in value {
    match character {
      '\\' => builder.write_string("\\\\")
      '"' => builder.write_string("\\\"")
      '\t' => builder.write_string("\\t")
      '\r' => builder.write_string("\\r")
      '\n' => builder.write_string("\\n")
      _ => builder.write_char(character)
    }
  }
  builder.write_char('"')
  builder.to_string()
}

///|
/// Render the source-like representation returned by just's `show()` builtin.
pub fn Value::display(self : Value) -> String {
  let elements = self.elements()
  match elements {
    [] => "[]"
    [value] => quote_element(value)
    values => "[" + values.map(quote_element).join(", ") + "]"
  }
}

///|
pub fn Value::join(self : Value, separator : String) -> String raise ValueError {
  match self {
    List(_) => self.elements().join(separator)
    _ => raise TypeMismatch(expected="list", actual=self.kind())
  }
}

///|
pub fn Value::kind(self : Value) -> String {
  match self {
    String(_) => "string"
    List(_) => "list"
    Bool(_) => "boolean"
  }
}

///|
pub(all) suberror ValueError {
  TypeMismatch(expected~ : String, actual~ : String)
} derive(Eq, Debug)
