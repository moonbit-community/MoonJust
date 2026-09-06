///|
fn upstream_json_source(text : String) -> String {
  let loaded = try! @loader.load_stdin(
    @utf8.encode(text),
    @source.SourceId::new(940),
    display_name="<stdin>",
  )
  let compilation = try! @semantic.compile(loaded.ast())
  inspect_json(loaded, compilation).stringify()
}

///|
test "upstream json::empty_justfile" {
  assert_eq(
    upstream_json_source(""),
    "{\"assignments\":{},\"first\":null,\"doc\":null,\"groups\":[],\"module_path\":\"\",\"modules\":{},\"aliases\":{},\"recipes\":{},\"settings\":{\"allow_duplicate_recipes\":false,\"allow_duplicate_variables\":false,\"default_list\":false,\"default_script\":false,\"dotenv_command\":[],\"dotenv_filename\":null,\"dotenv_load\":false,\"dotenv_override\":false,\"dotenv_path\":null,\"dotenv_required\":false,\"export\":false,\"fallback\":false,\"guards\":false,\"ignore_comments\":false,\"indentation\":null,\"lazy\":false,\"lists\":false,\"no_cd\":false,\"no_exit_message\":false,\"positional_arguments\":false,\"quiet\":false,\"shell\":null,\"tempdir\":null,\"unstable\":false,\"windows_powershell\":false,\"windows_shell\":null,\"working_directory\":null},\"source\":\"<stdin>\",\"unexports\":[],\"warnings\":[]}",
  )
}

///|
test "upstream json::simple" {
  assert_eq(
    upstream_json_source("foo:\n"),
    "{\"assignments\":{},\"first\":\"foo\",\"doc\":null,\"groups\":[],\"module_path\":\"\",\"modules\":{},\"aliases\":{},\"recipes\":{\"foo\":{\"attributes\":[],\"body\":[],\"dependencies\":[],\"doc\":null,\"name\":\"foo\",\"parameters\":[],\"priors\":0,\"private\":false,\"quiet\":false,\"namepath\":\"foo\",\"shebang\":false}},\"settings\":{\"allow_duplicate_recipes\":false,\"allow_duplicate_variables\":false,\"default_list\":false,\"default_script\":false,\"dotenv_command\":[],\"dotenv_filename\":null,\"dotenv_load\":false,\"dotenv_override\":false,\"dotenv_path\":null,\"dotenv_required\":false,\"export\":false,\"fallback\":false,\"guards\":false,\"ignore_comments\":false,\"indentation\":null,\"lazy\":false,\"lists\":false,\"no_cd\":false,\"no_exit_message\":false,\"positional_arguments\":false,\"quiet\":false,\"shell\":null,\"tempdir\":null,\"unstable\":false,\"windows_powershell\":false,\"windows_shell\":null,\"working_directory\":null},\"source\":\"<stdin>\",\"unexports\":[],\"warnings\":[]}",
  )
}

///|
test "upstream json::assignment" {
  assert_eq(
    upstream_json_source("x := 'foo'\n"),
    "{\"assignments\":{\"x\":{\"eager\":false,\"export\":false,\"name\":\"x\",\"private\":false,\"value\":\"foo\"}},\"first\":null,\"doc\":null,\"groups\":[],\"module_path\":\"\",\"modules\":{},\"aliases\":{},\"recipes\":{},\"settings\":{\"allow_duplicate_recipes\":false,\"allow_duplicate_variables\":false,\"default_list\":false,\"default_script\":false,\"dotenv_command\":[],\"dotenv_filename\":null,\"dotenv_load\":false,\"dotenv_override\":false,\"dotenv_path\":null,\"dotenv_required\":false,\"export\":false,\"fallback\":false,\"guards\":false,\"ignore_comments\":false,\"indentation\":null,\"lazy\":false,\"lists\":false,\"no_cd\":false,\"no_exit_message\":false,\"positional_arguments\":false,\"quiet\":false,\"shell\":null,\"tempdir\":null,\"unstable\":false,\"windows_powershell\":false,\"windows_shell\":null,\"working_directory\":null},\"source\":\"<stdin>\",\"unexports\":[],\"warnings\":[]}",
  )
}

///|
test "upstream json::alias" {
  let value = upstream_json_source("alias b := foo\nfoo:\n")
  assert_true(value.contains("\"aliases\":{\"b\":{"))
  assert_true(value.contains("\"target\":\"foo\""))
  assert_true(value.contains("\"first\":\"foo\""))
}

///|
test "upstream json::private" {
  let value = upstream_json_source("[private]\nfoo:\n")
  assert_true(value.contains("\"attributes\":[\"private\"]"))
  assert_true(value.contains("\"private\":true"))
}

///|
test "upstream json::settings" {
  let value = upstream_json_source("set quiet\n")
  assert_true(value.contains("\"quiet\":true"))
  assert_true(value.contains("\"settings\":{"))
}

///|
test "upstream json::dependencies" {
  let value = upstream_json_source("foo: bar\nbar:\n")
  assert_true(value.contains("\"dependencies\":[{"))
  assert_true(value.contains("\"recipe\":\"bar\""))
  assert_true(value.contains("\"priors\":1"))
}

///|
test "upstream json::parameters" {
  let value = upstream_json_source("foo a:\n")
  assert_true(value.contains("\"parameters\":[{"))
  assert_true(value.contains("\"name\":\"a\""))
  assert_true(value.contains("\"kind\":\"singular\""))
}

///|
test "upstream json::body" {
  let value = upstream_json_source("foo:\n echo hi\n")
  assert_true(value.contains("\"body\":[[\"echo hi\"]]"))
}

///|
test "upstream json::attribute" {
  let value = upstream_json_source("[doc: 'hello']\nfoo:\n")
  assert_true(value.contains("\"doc\":\"hello\""))
  assert_true(value.contains("\"attributes\":[{"))
}

///|
test "upstream json::arg_help" {
  let value = upstream_json_source("[arg('bar', help='hello')]\nfoo bar:\n")
  assert_true(value.contains("\"help\":\"hello\""))
  assert_true(value.contains("\"name\":\"bar\""))
}

///|
test "upstream json::arg_long" {
  let value = upstream_json_source("[arg('bar', long='BAR')]\nfoo bar:\n")
  assert_true(value.contains("\"long\":\"BAR\""))
}

///|
test "upstream json::arg_short" {
  let value = upstream_json_source("[arg('bar', short='B')]\nfoo bar:\n")
  assert_true(value.contains("\"short\":\"B\""))
}

///|
test "upstream json::arg_value" {
  let value = upstream_json_source(
    "[arg('bar', short='B', value='hello')]\nfoo bar:\n",
  )
  assert_true(value.contains("\"value\":\"hello\""))
}

///|
test "upstream json::arg_pattern" {
  let value = upstream_json_source("[arg('bar', pattern='BAR')]\nfoo bar:\n")
  assert_true(value.contains("\"pattern\":[\"BAR\"]"))
}

///|
test "upstream json::arg_flag" {
  let value = upstream_json_source(
    "set unstable\nset lists\n[arg('bar', long, flag)]\nfoo bar:\n",
  )
  assert_true(value.contains("\"flag\":true"))
  assert_true(value.contains("\"long\":\"bar\""))
}

///|
test "upstream json::arg_multiple" {
  let value = upstream_json_source(
    "set unstable\nset lists\n[arg('bar', long, multiple)]\nfoo bar:\n",
  )
  assert_true(value.contains("\"multiple\":true"))
}

///|
test "upstream json::private_assignment" {
  let value = upstream_json_source("[private]\nx := 'x'\n")
  assert_true(value.contains("\"private\":true"))
  assert_true(value.contains("\"name\":\"x\""))
}

///|
test "upstream json::quiet" {
  let value = upstream_json_source("@foo:\n")
  assert_true(value.contains("\"quiet\":true"))
}

///|
test "upstream json::shebang" {
  let value = upstream_json_source("foo:\n #!/bin/sh\n echo hi\n")
  assert_true(value.contains("\"shebang\":true"))
}

///|
test "upstream json::doc_comment" {
  let value = upstream_json_source("# hello\nfoo:\n")
  assert_true(value.contains("\"doc\":\"hello\""))
}

///|
test "upstream json::continue_attribute_default" {
  let value = upstream_json_source("[continue]\nfoo:\n")
  assert_true(value.contains("\"continue\":[]"))
}

///|
test "upstream json::continue_attribute_signals" {
  let value = upstream_json_source("[continue: 'SIGINT']\nfoo:\n")
  assert_true(value.contains("\"continue\":[\"SIGINT\"]"))
}

///|
test "upstream json::format_string" {
  let value = upstream_json_source("x := f'hello {{ 'world' }}'\n")
  assert_true(
    value.contains("\"value\":[\"format\",\"hello \",\"world\",\"\"]"),
  )
}

///|
test "upstream json::module_group" {
  let value = upstream_json_source("[group: 'build']\nfoo:\n")
  assert_true(value.contains("\"group\":\"build\""))
}

///|
test "upstream json::priors" {
  let value = upstream_json_source("foo: bar baz\nbar:\nbaz:\n")
  assert_true(value.contains("\"priors\":2"))
}

///|
test "upstream version::tests::current_version_is_valid" {
  assert_eq(version_line(), "moonjust v0.1.3-rc.1")
}
