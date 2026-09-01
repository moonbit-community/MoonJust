///|
fn recipe_names(size : Int) -> Array[String] {
  let names : Array[String] = []
  for index = 0; index < size; index = index + 1 {
    names.push("r" + index.to_string())
  }
  names
}

///|
fn recipe_lines(names : ArrayView[String], body : String) -> Array[String] {
  let lines : Array[String] = []
  for name in names {
    lines.push(name + ":\n    @" + body)
  }
  lines
}

///|
fn generated_source(kind : String, size : Int) -> String {
  let names = recipe_names(size)
  match kind {
    "dag" => {
      let lines : Array[String] = []
      lines.push("root: " + names.join(" ") + "\n    @:")
      for line in recipe_lines(names, ":") {
        lines.push(line)
      }
      lines.join("\n") + "\n"
    }
    "scripts" => {
      let lines : Array[String] = [
        "set default-script",
        "root: " + names.join(" ") + "\n    @:",
      ]
      for index, name in names {
        if index % 3 == 0 {
          lines.push(name + ":\n    #!/bin/sh\n    echo script")
        } else if index % 3 == 1 {
          lines.push(name + ":\n    @:")
        } else {
          lines.push(name + ":\n    @echo line")
        }
      }
      lines.join("\n") + "\n"
    }
    "modules" =>
      "set dotenv-load := true\n" +
      "set working-directory := 'work'\n" +
      "mod module\n" +
      "name := env_var('NAME')\n" +
      "root value:\n    @echo {{name}} {{value}}\n"
    "host" =>
      "set dotenv-load := true\n" +
      "import 'included.just'\n" +
      "mod module\n" +
      "root:\n    @:\n"
    _ => {
      let lines : Array[String] = []
      lines.push("root: " + names.join(" ") + "\n    @:")
      for line in recipe_lines(names, ":") {
        lines.push(line)
      }
      lines.join("\n") + "\n"
    }
  }
}

///|
fn workload(
  name : String,
  size : Int,
  kind : String,
  command : Array[String],
  source? : String = "",
  stdin_source? : String = "",
  calibration_ms? : Int64 = 0L,
) -> Workload {
  { name, size, kind, source, stdin_source, command, calibration_ms, }
}

///|
fn noops_workload(size : Int, calibration_ms : Int64) -> Workload {
  workload(
    "run-noops",
    size,
    "recipes",
    ["--justfile", "justfile", "root"],
    source=generated_source("recipes", size),
    calibration_ms~,
  )
}

///|
fn workloads() -> Array[Workload] {
  [
    workload("startup-version", 1, "startup", ["--version"]),
    workload(
      "check-1000",
      1000,
      "recipes",
      ["--justfile", "justfile", "--fmt", "--check"],
      source=generated_source("recipes", 1000),
    ),
    workload(
      "check-5000",
      5000,
      "recipes",
      ["--justfile", "justfile", "--fmt", "--check"],
      source=generated_source("recipes", 5000),
    ),
    workload(
      "summary-1000",
      1000,
      "recipes",
      ["--justfile", "justfile", "--summary"],
      source=generated_source("recipes", 1000),
    ),
    workload(
      "dry-run-dag-256",
      256,
      "dag",
      ["--justfile", "justfile", "--dry-run", "root"],
      source=generated_source("dag", 256),
    ),
    workload(
      "dry-run-dag-1000",
      1000,
      "dag",
      ["--justfile", "justfile", "--dry-run", "root"],
      source=generated_source("dag", 1000),
    ),
    workload(
      "modules-dotenv",
      1,
      "modules",
      ["--justfile", "justfile", "--dry-run", "root", "moonjust"],
      source=generated_source("modules", 1),
    ),
    workload(
      "script-recipes",
      96,
      "scripts",
      ["--justfile", "justfile", "--dry-run", "root"],
      source=generated_source("scripts", 96),
    ),
    workload(
      "stdin-file",
      512,
      "stdin",
      ["--justfile", "-", "--dry-run", "r0"],
      stdin_source=generated_source("recipes", 512),
    ),
    workload(
      "wasm-host-check",
      3,
      "host",
      ["--justfile", "justfile", "--summary"],
      source=generated_source("host", 3),
    ),
  ]
}

///|
async fn write_fixture_files(
  workload : Workload,
  directory : String,
) -> String? {
  if !workload.source.is_empty() {
    @fs.write_file(
      @path.Path(directory).join(Path("justfile")).to_string(),
      @utf8.encode(workload.source),
    )
  }
  match workload.kind {
    "modules" => {
      @fs.mkdir(
        @path.Path(directory).join(Path("module")).to_string(),
        recursive=true,
      )
      @fs.mkdir(
        @path.Path(directory).join(Path("work")).to_string(),
        recursive=true,
      )
      @fs.write_file(
        @path.Path(directory).join(Path(".env")).to_string(),
        @utf8.encode("NAME=moonjust\n"),
      )
      @fs.write_file(
        @path.Path(directory).join(Path("module/mod.just")).to_string(),
        @utf8.encode("sub:\n    @:\n"),
      )
      None
    }
    "host" => {
      @fs.mkdir(
        @path.Path(directory).join(Path("module")).to_string(),
        recursive=true,
      )
      @fs.mkdir(
        @path.Path(directory).join(Path("metadata")).to_string(),
        recursive=true,
      )
      @fs.write_file(
        @path.Path(directory).join(Path(".env")).to_string(),
        @utf8.encode("HOST_VALUE=moonjust\n"),
      )
      @fs.write_file(
        @path.Path(directory).join(Path("included.just")).to_string(),
        @utf8.encode("included := 'value'\n"),
      )
      @fs.write_file(
        @path.Path(directory).join(Path("module/mod.just")).to_string(),
        @utf8.encode("sub:\n    @:\n"),
      )
      @fs.write_file(
        @path.Path(directory).join(Path("metadata/entry")).to_string(),
        b"metadata\n",
      )
      None
    }
    "stdin" => {
      let path = @path.Path(directory).join(Path("stdin.just")).to_string()
      @fs.write_file(path, @utf8.encode(workload.stdin_source))
      Some(path)
    }
    _ => None
  }
}

///|
async fn prepare_fixture(workload : Workload) -> Fixture {
  let started = @async.now()
  let directory = @fs.tmpdir(prefix="moonjust-benchmark-" + workload.name)
  let stdin_path = write_fixture_files(workload, directory)
  { directory, stdin_path, setup_ms: @async.now() - started, }
}

///|
async fn remove_fixture(fixture : Fixture) -> Unit {
  @fs.rmdir(fixture.directory, recursive=true) catch {
    _ => ()
  }
}
