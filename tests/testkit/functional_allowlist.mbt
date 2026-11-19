///|
/// Host limits are reported outside successful comparisons. Keep each entry
/// tied to an upstream identity and its affected operating system.
pub fn deferred_host_behavior(upstream : String) -> (String, String)? {
  match upstream {
    "function::tests::dir_not_unicode" =>
      Some(
        (
          "unix", "the Wasm environment API omits values containing invalid UTF-8 before directory builtins can inspect them",
        ),
      )
    "non_unicode::non_unicode_invocation_directory_is_an_error" =>
      Some(
        (
          "linux", "moonrun cannot return a byte-valued Unix working directory to the Wasm guest",
        ),
      )
    _ => None
  }
}

///|
pub fn allowed_stderr_digest(
  upstream : String,
  fixture : String,
  reason : String,
  platform : String,
) -> String? {
  guard reason == "atomic-format-permissions" else { return None }
  match (upstream, fixture, platform) {
    ("format::ignore_disabled_indentation_setting", "upstream-b1-009", "unix")
    | (
      "format::indentation_flag_overrides_setting_format",
      "upstream-b1-011",
      "all",
    )
    | (
      "format::indentation_setting_format",
      "148-indentation-setting-format",
      "all",
    ) =>
      Some("d316b536c36a4ab1a6cdd4220d7a1bf6f832a3d42255161f120c0c841b811d0a")
    _ => None
  }
}
