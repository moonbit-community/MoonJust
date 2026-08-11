///|
fn digest(character : Char) -> String {
  character.to_string().repeat(64)
}

///|
fn cache_key(
  recipe? : String = "build",
  body? : String = "echo build",
  interpreter? : String = "sh",
  interpreter_arguments? : Array[String] = ["-cu"],
  environment? : Array[(String, String)] = [("Z", "last"), ("A", "first")],
  extension? : String = ".sh",
  working_directory? : String = "/workspace",
  positional? : Array[String] = ["release"],
  extra? : String = "profile=release",
  inputs? : Array[@cache.InputDigest] = [
    try! @cache.InputDigest::new("src/main.mbt", digest('a')),
  ],
  outputs? : Array[String] = ["target/app"],
) -> @cache.CacheKey {
  try! @cache.CacheKey::new(
    recipe,
    body,
    interpreter,
    interpreter_arguments~,
    environment~,
    extension~,
    working_directory~,
    positional~,
    extra~,
    inputs~,
    outputs~,
  )
}

///|
test "cache key is canonical across unordered fields" {
  let first = cache_key()
  let second = try! @cache.CacheKey::new(
    "build",
    "echo build",
    "sh",
    interpreter_arguments=["-cu"],
    environment=[("A", "first"), ("Z", "last")],
    extension=".sh",
    working_directory="/workspace",
    positional=["release"],
    extra="profile=release",
    inputs=[try! @cache.InputDigest::new("src/main.mbt", digest('a'))],
    outputs=["target/app"],
  )
  assert_eq(first.canonical(), second.canonical())
  assert_eq(first.digest(), second.digest())
  assert_eq(first.digest().length(), 64)
  let debug = first.debug_json()
  assert_true(debug.contains("\"executor\""))
  assert_true(debug.contains("\"working_directory\""))
}

///|
test "structural cache key debug output redacts executable values" {
  let key = try! @cache.CacheKey::new(
    "build",
    "TOP_SECRET_BODY",
    "sh",
    interpreter_arguments=["TOP_SECRET_ARGUMENT"],
    environment=[("TOKEN", "TOP_SECRET_ENVIRONMENT")],
    extra="TOP_SECRET_EXTRA",
  )
  let debug = "\{Repr(key)}"
  assert_true(debug.contains("body_bytes"))
  assert_true(debug.contains("TOKEN"))
  assert_false(debug.contains("TOP_SECRET"))
}

///|
test "cache key invalidates on body extra inputs and outputs" {
  let baseline = cache_key().digest()
  assert_true(cache_key(body="echo changed").digest() != baseline)
  assert_true(cache_key(extra="profile=debug").digest() != baseline)
  assert_true(
    cache_key(inputs=[try! @cache.InputDigest::new("src/main.mbt", digest('b'))]).digest() !=
    baseline,
  )
  assert_true(cache_key(outputs=["target/other"]).digest() != baseline)
  let variants = [
    cache_key(recipe="other-recipe"),
    cache_key(interpreter="bash"),
    cache_key(interpreter_arguments=["-eu"]),
    cache_key(environment=[("Z", "changed"), ("A", "first")]),
    cache_key(extension=".bash"),
    cache_key(working_directory="/other"),
    cache_key(positional=["debug"]),
  ]
  for variant in variants {
    assert_true(variant.digest() != baseline)
  }
}

///|
test "manifest round trip validates the complete contract" {
  let key = cache_key()
  let manifest = try! @cache.CacheManifest::new(
    key.digest(),
    key.recipe(),
    key.outputs(),
  )
  let encoded = manifest.encode()
  let decoded = try! @cache.validate_manifest(
    encoded,
    key.digest(),
    key.recipe(),
    key.outputs(),
  )
  assert_eq(decoded, manifest)
}

///|
test "untrusted output paths and duplicates are rejected" {
  for
    path in [
      "../secret", "/absolute", "C:/windows", "a\\b", "a//b", "a/./b", "a/../b",
    ] {
    try @cache.CacheManifest::new(digest('a'), "build", [path]) catch {
      InvalidPath(_) => ()
      error => fail("unexpected path error: \{Repr(error)}")
    } noraise {
      _ => fail("expected unsafe path rejection")
    }
  }
  try @cache.CacheManifest::new(digest('a'), "build", ["out", "out"]) catch {
    DuplicatePath("out") => ()
    error => fail("unexpected duplicate error: \{Repr(error)}")
  } noraise {
    _ => fail("expected duplicate output rejection")
  }
}

///|
test "cache input and manifest size limits are enforced" {
  let inputs : Array[@cache.InputDigest] = []
  for index in 0..<=@cache.MAX_INPUTS {
    inputs.push(
      try! @cache.InputDigest::new("src/input-\{index}.mbt", digest('a')),
    )
  }
  try @cache.CacheKey::new("build", "echo", "sh", inputs~) catch {
    TooManyInputs(count) => assert_eq(count, @cache.MAX_INPUTS + 1)
    error => fail("unexpected input limit error: \{Repr(error)}")
  } noraise {
    _ => fail("expected input count rejection")
  }
  let oversized = "界".repeat(@cache.MAX_MANIFEST_BYTES / 3 + 1)
  try @cache.decode_manifest(oversized) catch {
    ManifestTooLarge(size) => assert_true(size > @cache.MAX_MANIFEST_BYTES)
    error => fail("unexpected manifest limit error: \{Repr(error)}")
  } noraise {
    _ => fail("expected oversized manifest rejection")
  }
  try
    @cache.CacheManifest::new(
      digest('a'),
      "x".repeat(@cache.MAX_MANIFEST_BYTES),
      [],
    )
  catch {
    ManifestTooLarge(size) => assert_true(size > @cache.MAX_MANIFEST_BYTES)
    error => fail("unexpected encoded manifest limit error: \{Repr(error)}")
  } noraise {
    _ => fail("expected oversized encoded manifest rejection")
  }
}

///|
test "corrupt wrong-version and mismatched manifests never validate" {
  for
    text in [
      "{",
      "[]",
      "{\"algorithm\":\"moonjust-cache-key-v1+blake3\",\"key\":\"" +
      digest('a') +
      "\",\"outputs\":[],\"recipe\":\"build\",\"version\":2}",
      "{\"algorithm\":\"sha256\",\"key\":\"" +
      digest('a') +
      "\",\"outputs\":[],\"recipe\":\"build\",\"version\":1}",
    ] {
    try @cache.decode_manifest(text) catch {
      _ => ()
    } noraise {
      _ => fail("expected corrupt manifest rejection")
    }
  }
  let manifest = try! @cache.CacheManifest::new(digest('a'), "build", [
    "target/app",
  ])
  try
    @cache.validate_manifest(manifest.encode(), digest('b'), "build", [
      "target/app",
    ])
  catch {
    KeyMismatch => ()
    error => fail("unexpected mismatch error: \{Repr(error)}")
  } noraise {
    _ => fail("expected key mismatch")
  }
}
