///|
/// A noun phrase whose pluralization is selected by its count.
pub struct Count {
  singular : String
  plural : String
  count : Int
  numbered : Bool
}

///|
pub fn Count::numbered(singular : String, count : Int) -> Count {
  { singular, plural: singular + "s", count, numbered: true, }
}

///|
pub fn Count::numbered_irregular(
  singular : String,
  plural : String,
  count : Int,
) -> Count {
  { singular, plural, count, numbered: true, }
}

///|
pub fn Count::unnumbered(singular : String, count : Int) -> Count {
  { singular, plural: singular + "s", count, numbered: false, }
}

///|
pub fn Count::to_string(self : Count) -> String {
  let noun = if self.count == 1 { self.singular } else { self.plural }
  if self.numbered {
    self.count.to_string() + " " + noun
  } else {
    noun
  }
}

///|
pub fn tick(value : String) -> String {
  "`" + value + "`"
}

///|
pub fn join_list(
  values : ArrayView[String],
  conjunction : String,
  ticked? : Bool = false,
) -> String {
  let rendered = values.map(fn(value) {
    if ticked {
      tick(value)
    } else {
      value
    }
  })
  match rendered {
    [] => ""
    [single] => single
    [first, second] => first + " " + conjunction + " " + second
    _ => {
      let head = rendered[:rendered.length() - 1].join(", ")
      head + ", " + conjunction + " " + rendered[rendered.length() - 1]
    }
  }
}
