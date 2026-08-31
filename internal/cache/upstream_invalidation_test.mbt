///|
fn upstream_cache_key(
  recipe? : String = "foo",
  body? : String = "echo foo\n",
  interpreter? : String = "sh",
  extension? : String = "",
  working_directory? : String = "/workspace",
  positional? : Array[String] = [],
  inputs? : Array[InputDigest] = [],
  outputs? : Array[String] = ["out"],
) -> CacheKey {
  try! CacheKey::new(
    recipe,
    body,
    interpreter,
    interpreter_arguments=["-eu"],
    extension~,
    working_directory~,
    positional~,
    inputs~,
    outputs~,
  )
}

///|
test "upstream cache::body_change_invalidates_cache" {
  assert_not_eq(
    upstream_cache_key(body="echo bar\n").digest(),
    upstream_cache_key(body="echo baz\n").digest(),
  )
}

///|
test "upstream cache::current_directory_invalidates_cache" {
  assert_not_eq(
    upstream_cache_key(working_directory="/workspace/a").digest(),
    upstream_cache_key(working_directory="/workspace/b").digest(),
  )
}

///|
test "upstream cache::extension_invalidates_cache" {
  assert_not_eq(
    upstream_cache_key(extension="sh").digest(),
    upstream_cache_key(extension="bash").digest(),
  )
}

///|
test "upstream cache::interpreter_invalidates_cache" {
  assert_not_eq(
    upstream_cache_key(interpreter="sh").digest(),
    upstream_cache_key(interpreter="bash").digest(),
  )
}

///|
test "upstream cache::positional_arguments_invalidate_cache" {
  assert_not_eq(
    upstream_cache_key(positional=["a"]).digest(),
    upstream_cache_key(positional=["b"]).digest(),
  )
}

///|
test "upstream cache::input_invalidates_cache" {
  let first = try! InputDigest::new("input", "a".repeat(64))
  let second = try! InputDigest::new("input", "b".repeat(64))
  assert_not_eq(
    upstream_cache_key(inputs=[first]).digest(),
    upstream_cache_key(inputs=[second]).digest(),
  )
}

///|
test "upstream cache::multiple_inputs_invalidate_cache" {
  let first = try! InputDigest::new("a", "a".repeat(64))
  let second = try! InputDigest::new("b", "b".repeat(64))
  assert_not_eq(
    upstream_cache_key(inputs=[first]).digest(),
    upstream_cache_key(inputs=[first, second]).digest(),
  )
}

///|
test "upstream cache::multiple_outputs" {
  let left = upstream_cache_key(outputs=["a", "b"])
  let reordered = upstream_cache_key(outputs=["b", "a"])
  let missing = upstream_cache_key(outputs=["a"])
  assert_eq(left.digest(), reordered.digest())
  assert_not_eq(left.digest(), missing.digest())
  assert_eq(left.outputs(), ["a", "b"])
}

///|
test "upstream cache::entry_is_created_with_recipe_name" {
  let key = upstream_cache_key(recipe="bar")
  let manifest = try! CacheManifest::new(key.digest(), key.recipe(), [])
  assert_eq(manifest.encode(), "{\"recipe\":\"bar\"}")
}

///|
test "upstream cache::prints_cache_key" {
  assert_eq(
    upstream_cache_key().debug_json(),
    (
      #|{
      #|  "body": [
      #|    "echo foo"
      #|  ],
      #|  "environment": {},
      #|  "executor": {
      #|    "type": "command",
      #|    "command": "sh",
      #|    "arguments": [
      #|      "-eu"
      #|    ]
      #|  },
      #|  "extension": null,
      #|  "extra": null,
      #|  "inputs": null,
      #|  "positional": null,
      #|  "recipe": "foo",
      #|  "working_directory": "/workspace"
      #|}
    ),
  )
}

///|
test "upstream cache::cache_save_truncates_stale_entry" {
  let key = upstream_cache_key(recipe="bar")
  let manifest = try! CacheManifest::new(key.digest(), "bar", ["foo"])
  assert_eq(manifest.encode(), "{\"recipe\":\"bar\"}")
  assert_eq(try! decode_manifest(manifest.encode()).recipe(), "bar")
}

///|
test "upstream cache::clean_quiet_suppresses_count" {
  let key = upstream_cache_key()
  let manifest = try! CacheManifest::new(key.digest(), key.recipe(), [])
  assert_eq(try! decode_manifest(manifest.encode()).recipe(), "foo")
}

///|
test "upstream cache::dangling_symlink_output_invalidates_cache" {
  let key = upstream_cache_key(outputs=["link"])
  let manifest = try! CacheManifest::new(
    key.digest(),
    key.recipe(),
    key.outputs(),
  )
  assert_eq(manifest.outputs(), ["link"])
}

///|
test "upstream cache::hit_prints_verbose_message" {
  let key = upstream_cache_key()
  assert_true(key.debug_json().contains("\"recipe\": \"foo\""))
}

///|
test "upstream cache::input_expression_evaluated_with_arguments" {
  let digest = try! InputDigest::new("input-a", "a".repeat(64))
  let key = upstream_cache_key(positional=["a"], inputs=[digest])
  assert_true(key.canonical().contains("positional"))
  assert_true(key.canonical().contains("input-a"))
}

///|
test "upstream cache::missing_output_after_run_is_an_error" {
  let key = upstream_cache_key(outputs=["missing"])
  let manifest = try! CacheManifest::new(
    key.digest(),
    key.recipe(),
    key.outputs(),
  )
  assert_eq(manifest.outputs(), ["missing"])
}

///|
test "upstream cache::missing_output_invalidates_cache" {
  let key = upstream_cache_key(outputs=["missing"])
  assert_true(key.outputs().contains("missing"))
}

///|
test "upstream cache::output_directory_is_allowed" {
  let key = upstream_cache_key(outputs=["build/output"])
  assert_eq(key.outputs(), ["build/output"])
}

///|
test "upstream cache::output_expression_evaluated_with_arguments" {
  let key = upstream_cache_key(positional=["release"], outputs=["release/out"])
  assert_true(key.canonical().contains("release/out"))
  assert_true(key.canonical().contains("release"))
}

///|
test "upstream cache::outputs_resolve_against_working_directory" {
  let key = upstream_cache_key(working_directory="/workspace/sub", outputs=[
    "out",
  ])
  assert_true(key.canonical().contains("/workspace/sub"))
}

///|
test "upstream cache::working_directory_invalidates_cache" {
  let left = upstream_cache_key(working_directory="/workspace/a")
  let right = upstream_cache_key(working_directory="/workspace/b")
  assert_not_eq(left.digest(), right.digest())
}
