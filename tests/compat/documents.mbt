///|
const DOCUMENT_ROOT = "tests/compatibility/upstream/just-1.59.0/source"

///|
priv enum DocumentContract {
  ReadmeBlocks
  ExampleFiles
  Changelog
  RepositoryOnly(String)
}

///|
fn document_contract(id : String) -> DocumentContract? {
  match id {
    "readme::readme" => Some(ReadmeBlocks)
    "examples::examples" => Some(ExampleFiles)
    "changelog::print_changelog" => Some(Changelog)
    "readme::heading_levels_are_not_skipped" =>
      Some(RepositoryOnly("Heading hierarchy of the upstream README"))
    "readme::h1_and_h2_headings_are_setext" =>
      Some(RepositoryOnly("Markdown spelling of upstream README headings"))
    "constants::tests::readme_table" =>
      Some(
        RepositoryOnly("Generated Rust constants table in the upstream README"),
      )
    _ => None
  }
}

///|
fn DocumentContract::evidence(
  self : DocumentContract,
) -> (String, String, String) {
  match self {
    ReadmeBlocks =>
      (
        "document-oracle",
        DOCUMENT_ROOT + "/README.md",
        "Both CLIs exit successfully for --dump on each pinned just fence",
      )
    ExampleFiles =>
      (
        "document-oracle",
        DOCUMENT_ROOT + "/examples",
        "Both CLIs exit successfully for --justfile FILE --dump on every pinned example",
      )
    Changelog =>
      (
        "document-oracle", "just --changelog", "Both CLIs exit 0 with empty stderr and the pinned upstream changelog bytes",
      )
    RepositoryOnly(reason) =>
      ("repository-only", DOCUMENT_ROOT + "/README.md", reason)
  }
}

///|
fn readme_just_blocks(markdown : String) -> Array[(Int32, String)] raise {
  let blocks = []
  let mut start : Int32? = None
  let body = StringBuilder()
  for i, line in markdown.split("\n").collect() {
    match start {
      Some(number) if line == "```" => {
        blocks.push((number, body.to_string()))
        body.reset()
        start = None
      }
      Some(_) => {
        body.write_string(line.to_owned())
        body.write_char('\n')
      }
      None if line == "```just" => start = Some(i + 1)
      None => ()
    }
  }
  if start is Some(line) {
    fail("unclosed README fence on line " + line.to_string())
  }
  blocks
}

///|
async fn document_command(
  program : @testkit.PreparedProgram,
  filename : String,
  source : Bytes,
  args : Array[String],
) -> @testkit.RunResult {
  let root = @fs.tmpdir(prefix="moonjust-document")
  defer @fs.remove(root, recursive=true)
  @fs.write_binary(join(root, filename), source)
  @testkit.run_prepared(
    program,
    args,
    cwd=root,
    extra_env=isolated_environment(root),
    inherit_env=false,
  )
}

///|
async fn check_document(
  contract : DocumentContract,
  official : @testkit.PreparedProgram,
  candidate : @testkit.PreparedProgram,
) -> Unit {
  async fn dump(
    label : String,
    name : String,
    input : Bytes,
    args : Array[String],
  ) -> Unit {
    for (side, program) in [("official", official), ("candidate", candidate)] {
      let result = document_command(program, name, input, args)
      if result.status != 0 {
        let stderr = @utf8.decode(result.stderr) catch {
          _ => "(non-UTF-8 stderr)"
        }
        fail(
          label +
          " " +
          side +
          " --dump exited " +
          result.status.to_string() +
          ": " +
          stderr,
        )
      }
    }
  }
  match contract {
    ReadmeBlocks => {
      let blocks = readme_just_blocks(
        @fs.read_text(join(DOCUMENT_ROOT, "README.md")),
      )
      guard blocks.length() == 195 else {
        fail("expected 195 just fences in the pinned README")
      }
      for (line, source) in blocks {
        dump(
          "README.md:" + line.to_string(),
          "justfile",
          @utf8.encode(source),
          ["--dump"],
        )
      }
    }
    ExampleFiles => {
      let dir = join(DOCUMENT_ROOT, "examples")
      let files = @fs.readdir(dir, include_hidden=true, sort=true)
      guard files.length() == 7 else {
        fail("expected 7 files in the pinned examples directory")
      }
      for file in files {
        dump(file, file, @fs.read_binary(join(dir, file)), [
          "--justfile", file, "--dump",
        ])
      }
    }
    Changelog => {
      let reference = document_command(official, "justfile", b"", [
        "--changelog",
      ])
      guard reference.status == 0 &&
        reference.stderr.is_empty() &&
        @crypto.bytes_to_hex_string(@crypto.sha256(reference.stdout)) ==
        "0dce88c74adb5a3d4b3418a66bd3a75be54fd85f9eee7de44de5f593b87462a2" else {
        fail("official --changelog differs from pinned CHANGELOG.md")
      }
      let actual = document_command(candidate, "justfile", b"", ["--changelog"])
      guard actual.status == 0 &&
        actual.stderr.is_empty() &&
        actual.stdout == reference.stdout else {
        fail(
          "candidate --changelog differs from official status, stdout or stderr",
        )
      }
    }
    RepositoryOnly(_) => fail("repository-only identity has no CLI assertion")
  }
}
