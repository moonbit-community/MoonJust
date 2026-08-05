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
    List(_) | Bool(_) => None
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
    String(value) => !value.is_empty()
    List(value) => value.length() > 0
  }
}

///|
/// Render a value with just-compatible list quoting and stable ordering.
pub fn Value::to_string(self : Value) -> String {
  match self {
    String(value) => value
    Bool(true) => "true"
    Bool(false) => "false"
    List(values) => {
      let builder = StringBuilder()
      builder.write_char('[')
      for index, value in values {
        if index > 0 {
          builder.write_string(", ")
        }
        builder.write_char('"')
        builder.write_string(
          value
          .to_string()
          .replace(old="\\", new="\\\\")
          .replace(old="\"", new="\\\""),
        )
        builder.write_char('"')
      }
      builder.write_char(']')
      builder.to_string()
    }
  }
}

///|
pub fn Value::join(self : Value, separator : String) -> String raise ValueError {
  match self {
    List(values) => {
      let result : Array[String] = []
      for value in values {
        match value.as_string() {
          Some(text) => result.push(text)
          None => raise TypeMismatch(expected="string", actual=value.kind())
        }
      }
      result.join(separator)
    }
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
