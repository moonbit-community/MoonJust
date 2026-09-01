///|
fn median(values : Array[Int64]) -> Int64 {
  values.sort()
  values[values.length() / 2]
}

///|
fn median_double(values : Array[Double]) -> Double {
  values.sort()
  values[values.length() / 2]
}

///|
fn p95(values : Array[Int64]) -> Int64 {
  values.sort()
  let index = (values.length() * 95 + 99) / 100 - 1
  values[index.max(0).min(values.length() - 1)]
}

///|
fn ratio(candidate : Int64, official : Int64) -> Double {
  if official == 0L {
    if candidate == 0L {
      1.0
    } else {
      99.0
    }
  } else {
    candidate.to_double() / official.to_double()
  }
}

///|
fn ratio_ci(
  candidate : Array[Int64],
  official : Array[Int64],
) -> (Double, Double) {
  let ratios : Array[Double] = []
  let count = candidate.length().min(official.length())
  for index = 0; index < count; index = index + 1 {
    ratios.push(ratio(candidate[index], official[index]))
  }
  if ratios.is_empty() {
    return (0.0, 0.0)
  }
  ratios.sort()
  let low = (ratios.length().to_double() * 0.025)
    .to_int()
    .max(0)
    .min(ratios.length() - 1)
  let high = (ratios.length().to_double() * 0.975)
    .to_int()
    .max(0)
    .min(ratios.length() - 1)
  (ratios[low], ratios[high])
}

///|
fn int64_json(values : ArrayView[Int64]) -> String {
  let items : Array[String] = []
  for value in values {
    items.push(value.to_string())
  }
  "[" + items.join(",") + "]"
}

///|
fn double_json(values : ArrayView[Double]) -> String {
  let items : Array[String] = []
  for value in values {
    items.push(value.to_string())
  }
  "[" + items.join(",") + "]"
}
