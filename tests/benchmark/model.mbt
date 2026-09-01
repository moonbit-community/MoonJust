///|
priv struct Workload {
  name : String
  size : Int
  kind : String
  source : String
  stdin_source : String
  command : Array[String]
  calibration_ms : Int64
}

///|
priv struct Fixture {
  directory : String
  stdin_path : String?
  setup_ms : Int64
}

///|
priv struct BenchmarkSettings {
  profile : String
  batches : Int
  rounds : Int
  warmups : Int
  target : String
  output_path : String
  enforce : Bool
}

///|
priv struct Measurements {
  candidate : Array[Int64]
  official : Array[Int64]
  batch_ratios : Array[Double]
  behavior_ms : Int64
}
