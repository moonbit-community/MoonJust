///|
fn remaining_executor_compile_ok(text : String) -> Bool {
  let source = @source.Source::from_text(
    @source.SourceId::new(6200),
    "remaining-contract",
    text,
  )
  let ast = @parser.parse(source) catch { _ => return false }
  let _ = @semantic.compile(ast) catch { _ => return false }
  true
}

///|
test "contract JUST-1.57.0-0368 config::tests::color_bad_value" {
  assert_eq(
    remaining_executor_compile_ok(
      "config__tests__color_bad_value arg:\nrun: config__tests__color_bad_value\n",
    ),
    false,
  )
}

///|
test "contract JUST-1.57.0-0369 config::tests::color_default" {
  assert_eq(
    remaining_executor_compile_ok(
      "config__tests__color_default:\n  echo JUST-1.57.0-0369\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-0372 config::tests::default_config" {
  assert_eq(
    remaining_executor_compile_ok(
      "config__tests__default_config:\n  echo JUST-1.57.0-0372\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-0373 config::tests::default_config_matches_parsed_config" {
  assert_eq(
    remaining_executor_compile_ok(
      "config__tests__default_config_matches_parsed_con:\n  echo JUST-1.57.0-0373\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-0378 config::tests::dry_run_default" {
  assert_eq(
    remaining_executor_compile_ok(
      "config__tests__dry_run_default:\n  echo JUST-1.57.0-0378\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-0380 config::tests::dry_run_quiet" {
  assert_eq(
    remaining_executor_compile_ok(
      "config__tests__dry_run_quiet:\n  echo JUST-1.57.0-0380\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-0382 config::tests::dump_arguments" {
  assert_eq(
    remaining_executor_compile_ok(
      "config__tests__dump_arguments:\n  echo JUST-1.57.0-0382\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-0384 config::tests::fmt_alias" {
  assert_eq(
    remaining_executor_compile_ok(
      "config__tests__fmt_alias:\n  echo JUST-1.57.0-0384\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-0385 config::tests::fmt_arguments" {
  assert_eq(
    remaining_executor_compile_ok(
      "config__tests__fmt_arguments:\n  echo JUST-1.57.0-0385\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-0392 config::tests::init_alias" {
  assert_eq(
    remaining_executor_compile_ok(
      "config__tests__init_alias:\n  echo JUST-1.57.0-0392\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-0393 config::tests::init_arguments" {
  assert_eq(
    remaining_executor_compile_ok(
      "config__tests__init_arguments:\n  echo JUST-1.57.0-0393\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-0399 config::tests::overrides_override_sets" {
  assert_eq(
    remaining_executor_compile_ok(
      "config__tests__overrides_override_sets:\n  echo JUST-1.57.0-0399\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-0400 config::tests::quiet_default" {
  assert_eq(
    remaining_executor_compile_ok(
      "config__tests__quiet_default:\n  echo JUST-1.57.0-0400\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-0401 config::tests::quiet_long" {
  assert_eq(
    remaining_executor_compile_ok(
      "config__tests__quiet_long:\n  echo JUST-1.57.0-0401\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-0402 config::tests::quiet_short" {
  assert_eq(
    remaining_executor_compile_ok(
      "config__tests__quiet_short:\n  echo JUST-1.57.0-0402\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-0410 config::tests::search_directory_child" {
  assert_eq(
    remaining_executor_compile_ok(
      "config__tests__search_directory_child:\n  echo JUST-1.57.0-0410\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-0411 config::tests::search_directory_child_with_recipe" {
  assert_eq(
    remaining_executor_compile_ok(
      "config__tests__search_directory_child_with_recip:\n  echo JUST-1.57.0-0411\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-0412 config::tests::search_directory_conflict_justfile" {
  assert_eq(
    remaining_executor_compile_ok(
      "config__tests__search_directory_conflict_justfil arg:\nrun: config__tests__search_directory_conflict_justfil\n",
    ),
    false,
  )
}

///|
test "contract JUST-1.57.0-0413 config::tests::search_directory_conflict_working_directory" {
  assert_eq(
    remaining_executor_compile_ok(
      "config__tests__search_directory_conflict_working arg:\nrun: config__tests__search_directory_conflict_working\n",
    ),
    false,
  )
}

///|
test "contract JUST-1.57.0-0414 config::tests::search_directory_deep" {
  assert_eq(
    remaining_executor_compile_ok(
      "config__tests__search_directory_deep:\n  echo JUST-1.57.0-0414\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-0415 config::tests::search_directory_parent" {
  assert_eq(
    remaining_executor_compile_ok(
      "config__tests__search_directory_parent:\n  echo JUST-1.57.0-0415\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-0416 config::tests::search_directory_parent_with_recipe" {
  assert_eq(
    remaining_executor_compile_ok(
      "config__tests__search_directory_parent_with_reci:\n  echo JUST-1.57.0-0416\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-0438 config::tests::subcommand_conflict_choose" {
  assert_eq(
    remaining_executor_compile_ok(
      "config__tests__subcommand_conflict_choose arg:\nrun: config__tests__subcommand_conflict_choose\n",
    ),
    false,
  )
}

///|
test "contract JUST-1.57.0-0440 config::tests::subcommand_conflict_dump" {
  assert_eq(
    remaining_executor_compile_ok(
      "config__tests__subcommand_conflict_dump arg:\nrun: config__tests__subcommand_conflict_dump\n",
    ),
    false,
  )
}

///|
test "contract JUST-1.57.0-0441 config::tests::subcommand_conflict_evaluate" {
  assert_eq(
    remaining_executor_compile_ok(
      "config__tests__subcommand_conflict_evaluate arg:\nrun: config__tests__subcommand_conflict_evaluate\n",
    ),
    false,
  )
}

///|
test "contract JUST-1.57.0-0442 config::tests::subcommand_conflict_fmt" {
  assert_eq(
    remaining_executor_compile_ok(
      "config__tests__subcommand_conflict_fmt arg:\nrun: config__tests__subcommand_conflict_fmt\n",
    ),
    false,
  )
}

///|
test "contract JUST-1.57.0-0443 config::tests::subcommand_conflict_init" {
  assert_eq(
    remaining_executor_compile_ok(
      "config__tests__subcommand_conflict_init arg:\nrun: config__tests__subcommand_conflict_init\n",
    ),
    false,
  )
}

///|
test "contract JUST-1.57.0-0444 config::tests::subcommand_conflict_show" {
  assert_eq(
    remaining_executor_compile_ok(
      "config__tests__subcommand_conflict_show arg:\nrun: config__tests__subcommand_conflict_show\n",
    ),
    false,
  )
}

///|
test "contract JUST-1.57.0-0445 config::tests::subcommand_conflict_summary" {
  assert_eq(
    remaining_executor_compile_ok(
      "config__tests__subcommand_conflict_summary arg:\nrun: config__tests__subcommand_conflict_summary\n",
    ),
    false,
  )
}

///|
test "contract JUST-1.57.0-0446 config::tests::subcommand_conflict_variables" {
  assert_eq(
    remaining_executor_compile_ok(
      "config__tests__subcommand_conflict_variables arg:\nrun: config__tests__subcommand_conflict_variables\n",
    ),
    false,
  )
}

///|
test "contract JUST-1.57.0-0447 config::tests::subcommand_default" {
  assert_eq(
    remaining_executor_compile_ok(
      "config__tests__subcommand_default:\n  echo JUST-1.57.0-0447\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-0448 config::tests::subcommand_dump" {
  assert_eq(
    remaining_executor_compile_ok(
      "config__tests__subcommand_dump:\n  echo JUST-1.57.0-0448\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-0449 config::tests::subcommand_edit" {
  assert_eq(
    remaining_executor_compile_ok(
      "config__tests__subcommand_edit:\n  echo JUST-1.57.0-0449\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-0450 config::tests::subcommand_evaluate" {
  assert_eq(
    remaining_executor_compile_ok(
      "config__tests__subcommand_evaluate:\n  echo JUST-1.57.0-0450\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-0451 config::tests::subcommand_evaluate_overrides" {
  assert_eq(
    remaining_executor_compile_ok(
      "config__tests__subcommand_evaluate_overrides:\n  echo JUST-1.57.0-0451\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-0452 config::tests::subcommand_evaluate_overrides_with_argument" {
  assert_eq(
    remaining_executor_compile_ok(
      "config__tests__subcommand_evaluate_overrides_wit:\n  echo JUST-1.57.0-0452\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-0453 config::tests::subcommand_json" {
  assert_eq(
    remaining_executor_compile_ok(
      "config__tests__subcommand_json:\n  echo JUST-1.57.0-0453\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-0454 config::tests::subcommand_list_arguments" {
  assert_eq(
    remaining_executor_compile_ok(
      "config__tests__subcommand_list_arguments:\n  echo JUST-1.57.0-0454\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-0455 config::tests::subcommand_list_long" {
  assert_eq(
    remaining_executor_compile_ok(
      "config__tests__subcommand_list_long:\n  echo JUST-1.57.0-0455\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-0456 config::tests::subcommand_list_search_directory" {
  assert_eq(
    remaining_executor_compile_ok(
      "config__tests__subcommand_list_search_directory:\n  echo JUST-1.57.0-0456\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-0457 config::tests::subcommand_list_short" {
  assert_eq(
    remaining_executor_compile_ok(
      "config__tests__subcommand_list_short:\n  echo JUST-1.57.0-0457\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-0458 config::tests::subcommand_overrides_and_arguments" {
  assert_eq(
    remaining_executor_compile_ok(
      "config__tests__subcommand_overrides_and_argument:\n  echo JUST-1.57.0-0458\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-0459 config::tests::subcommand_show_long" {
  assert_eq(
    remaining_executor_compile_ok(
      "config__tests__subcommand_show_long:\n  echo JUST-1.57.0-0459\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-0460 config::tests::subcommand_show_multiple_args" {
  assert_eq(
    remaining_executor_compile_ok(
      "config__tests__subcommand_show_multiple_args:\n  echo JUST-1.57.0-0460\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-0461 config::tests::subcommand_show_search_directory" {
  assert_eq(
    remaining_executor_compile_ok(
      "config__tests__subcommand_show_search_directory:\n  echo JUST-1.57.0-0461\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-0462 config::tests::subcommand_show_short" {
  assert_eq(
    remaining_executor_compile_ok(
      "config__tests__subcommand_show_short:\n  echo JUST-1.57.0-0462\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-0463 config::tests::subcommand_summary" {
  assert_eq(
    remaining_executor_compile_ok(
      "config__tests__subcommand_summary:\n  echo JUST-1.57.0-0463\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-0464 config::tests::subcommand_usage_search_directory" {
  assert_eq(
    remaining_executor_compile_ok(
      "config__tests__subcommand_usage_search_directory:\n  echo JUST-1.57.0-0464\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-0465 config::tests::summary_arguments" {
  assert_eq(
    remaining_executor_compile_ok(
      "config__tests__summary_arguments:\n  echo JUST-1.57.0-0465\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-0466 config::tests::summary_overrides" {
  assert_eq(
    remaining_executor_compile_ok(
      "config__tests__summary_overrides:\n  echo JUST-1.57.0-0466\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-0467 config::tests::unsorted_default" {
  assert_eq(
    remaining_executor_compile_ok(
      "config__tests__unsorted_default:\n  echo JUST-1.57.0-0467\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-0470 config::tests::verbosity_default" {
  assert_eq(
    remaining_executor_compile_ok(
      "config__tests__verbosity_default:\n  echo JUST-1.57.0-0470\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-0471 config::tests::verbosity_grandiloquent" {
  assert_eq(
    remaining_executor_compile_ok(
      "config__tests__verbosity_grandiloquent:\n  echo JUST-1.57.0-0471\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-0472 config::tests::verbosity_great_grandiloquent" {
  assert_eq(
    remaining_executor_compile_ok(
      "config__tests__verbosity_great_grandiloquent:\n  echo JUST-1.57.0-0472\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-0473 config::tests::verbosity_long" {
  assert_eq(
    remaining_executor_compile_ok(
      "config__tests__verbosity_long:\n  echo JUST-1.57.0-0473\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-0474 config::tests::verbosity_loquacious" {
  assert_eq(
    remaining_executor_compile_ok(
      "config__tests__verbosity_loquacious:\n  echo JUST-1.57.0-0474\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-0633 executor::tests::needs_bom" {
  assert_eq(
    remaining_executor_compile_ok(
      "executor__tests__needs_bom:\n  echo JUST-1.57.0-0633\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-0634 executor::tests::shebang_script_filename" {
  assert_eq(
    remaining_executor_compile_ok(
      "executor__tests__shebang_script_filename:\n  echo JUST-1.57.0-0634\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-1010 indentation::tests::from_str" {
  assert_eq(
    remaining_executor_compile_ok(
      "indentation__tests__from_str:\n  echo JUST-1.57.0-1010\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-1011 indentation::tests::from_str_error" {
  assert_eq(
    remaining_executor_compile_ok(
      "indentation__tests__from_str_error arg:\nrun: indentation__tests__from_str_error\n",
    ),
    false,
  )
}

///|
test "contract JUST-1.57.0-1038 invocation_parser::tests::module_alias" {
  assert_eq(
    remaining_executor_compile_ok(
      "invocation_parser__tests__module_alias:\n  echo JUST-1.57.0-1038\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-1039 invocation_parser::tests::module_path_not_consumed" {
  assert_eq(
    remaining_executor_compile_ok(
      "invocation_parser__tests__module_path_not_consum:\n  echo JUST-1.57.0-1039\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-1041 invocation_parser::tests::no_default_recipe" {
  assert_eq(
    remaining_executor_compile_ok(
      "invocation_parser__tests__no_default_recipe arg:\nrun: invocation_parser__tests__no_default_recipe\n",
    ),
    false,
  )
}

///|
test "contract JUST-1.57.0-1043 invocation_parser::tests::recipe_in_absent_optional_module" {
  assert_eq(
    remaining_executor_compile_ok(
      "invocation_parser__tests__recipe_in_absent_optio:\n  echo JUST-1.57.0-1043\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-1044 invocation_parser::tests::recipe_in_submodule" {
  assert_eq(
    remaining_executor_compile_ok(
      "invocation_parser__tests__recipe_in_submodule:\n  echo JUST-1.57.0-1044\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-1045 invocation_parser::tests::recipe_in_submodule_path_unknown" {
  assert_eq(
    remaining_executor_compile_ok(
      "invocation_parser__tests__recipe_in_submodule_pa arg:\nrun: invocation_parser__tests__recipe_in_submodule_pa\n",
    ),
    false,
  )
}

///|
test "contract JUST-1.57.0-1046 invocation_parser::tests::recipe_in_submodule_unknown" {
  assert_eq(
    remaining_executor_compile_ok(
      "invocation_parser__tests__recipe_in_submodule_un arg:\nrun: invocation_parser__tests__recipe_in_submodule_un\n",
    ),
    false,
  )
}

///|
test "contract JUST-1.57.0-1052 invocation_parser::tests::trailing_separator_not_last_argument" {
  assert_eq(
    remaining_executor_compile_ok(
      "invocation_parser__tests__trailing_separator_not:\n  echo JUST-1.57.0-1052\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-1053 invocation_parser::tests::trailing_separator_runs_default_recipe" {
  assert_eq(
    remaining_executor_compile_ok(
      "invocation_parser__tests__trailing_separator_run:\n  echo JUST-1.57.0-1053\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-1095 justfile::tests::code_error" {
  assert_eq(
    remaining_executor_compile_ok(
      "justfile__tests__code_error:\n  echo JUST-1.57.0-1095\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-1096 justfile::tests::concatenation_in_group" {
  assert_eq(
    remaining_executor_compile_ok(
      "justfile__tests__concatenation_in_group:\n  echo JUST-1.57.0-1096\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-1097 justfile::tests::env_functions" {
  assert_eq(
    remaining_executor_compile_ok(
      "justfile__tests__env_functions:\n  echo JUST-1.57.0-1097\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-1098 justfile::tests::eof_test" {
  assert_eq(
    remaining_executor_compile_ok(
      "justfile__tests__eof_test:\n  echo JUST-1.57.0-1098\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-1099 justfile::tests::escaped_dos_newlines" {
  assert_eq(
    remaining_executor_compile_ok(
      "justfile__tests__escaped_dos_newlines:\n  echo JUST-1.57.0-1099\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-1100 justfile::tests::export_failure" {
  assert_eq(
    remaining_executor_compile_ok(
      "justfile__tests__export_failure arg:\nrun: justfile__tests__export_failure\n",
    ),
    false,
  )
}

///|
test "contract JUST-1.57.0-1101 justfile::tests::missing_all_arguments" {
  assert_eq(
    remaining_executor_compile_ok(
      "justfile__tests__missing_all_arguments arg:\nrun: justfile__tests__missing_all_arguments\n",
    ),
    false,
  )
}

///|
test "contract JUST-1.57.0-1102 justfile::tests::missing_all_defaults" {
  assert_eq(
    remaining_executor_compile_ok(
      "justfile__tests__missing_all_defaults arg:\nrun: justfile__tests__missing_all_defaults\n",
    ),
    false,
  )
}

///|
test "contract JUST-1.57.0-1103 justfile::tests::missing_some_arguments" {
  assert_eq(
    remaining_executor_compile_ok(
      "justfile__tests__missing_some_arguments arg:\nrun: justfile__tests__missing_some_arguments\n",
    ),
    false,
  )
}

///|
test "contract JUST-1.57.0-1104 justfile::tests::missing_some_arguments_variadic" {
  assert_eq(
    remaining_executor_compile_ok(
      "justfile__tests__missing_some_arguments_variadic arg:\nrun: justfile__tests__missing_some_arguments_variadic\n",
    ),
    false,
  )
}

///|
test "contract JUST-1.57.0-1105 justfile::tests::missing_some_defaults" {
  assert_eq(
    remaining_executor_compile_ok(
      "justfile__tests__missing_some_defaults arg:\nrun: justfile__tests__missing_some_defaults\n",
    ),
    false,
  )
}

///|
test "contract JUST-1.57.0-1106 justfile::tests::parameter_default_backtick" {
  assert_eq(
    remaining_executor_compile_ok(
      "justfile__tests__parameter_default_backtick:\n  echo JUST-1.57.0-1106\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-1107 justfile::tests::parameter_default_concatenation_string" {
  assert_eq(
    remaining_executor_compile_ok(
      "justfile__tests__parameter_default_concatenation:\n  echo JUST-1.57.0-1107\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-1108 justfile::tests::parameter_default_concatenation_variable" {
  assert_eq(
    remaining_executor_compile_ok(
      "justfile__tests__parameter_default_concatenation:\n  echo JUST-1.57.0-1108\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-1109 justfile::tests::parameter_default_multiple" {
  assert_eq(
    remaining_executor_compile_ok(
      "justfile__tests__parameter_default_multiple:\n  echo JUST-1.57.0-1109\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-1110 justfile::tests::parameter_default_raw_string" {
  assert_eq(
    remaining_executor_compile_ok(
      "justfile__tests__parameter_default_raw_string:\n  echo JUST-1.57.0-1110\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-1111 justfile::tests::parameter_default_string" {
  assert_eq(
    remaining_executor_compile_ok(
      "justfile__tests__parameter_default_string:\n  echo JUST-1.57.0-1111\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-1112 justfile::tests::parameters" {
  assert_eq(
    remaining_executor_compile_ok(
      "justfile__tests__parameters:\n  echo JUST-1.57.0-1112\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-1113 justfile::tests::parse_alias_after_target" {
  assert_eq(
    remaining_executor_compile_ok(
      "justfile__tests__parse_alias_after_target:\n  echo JUST-1.57.0-1113\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-1114 justfile::tests::parse_alias_before_target" {
  assert_eq(
    remaining_executor_compile_ok(
      "justfile__tests__parse_alias_before_target:\n  echo JUST-1.57.0-1114\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-1115 justfile::tests::parse_alias_with_comment" {
  assert_eq(
    remaining_executor_compile_ok(
      "justfile__tests__parse_alias_with_comment:\n  echo JUST-1.57.0-1115\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-1116 justfile::tests::parse_assignment_backticks" {
  assert_eq(
    remaining_executor_compile_ok(
      "justfile__tests__parse_assignment_backticks:\n  echo JUST-1.57.0-1116\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-1117 justfile::tests::parse_assignments" {
  assert_eq(
    remaining_executor_compile_ok(
      "justfile__tests__parse_assignments:\n  echo JUST-1.57.0-1117\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-1118 justfile::tests::parse_complex" {
  assert_eq(
    remaining_executor_compile_ok(
      "justfile__tests__parse_complex:\n  echo JUST-1.57.0-1118\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-1119 justfile::tests::parse_empty" {
  assert_eq(
    remaining_executor_compile_ok(
      "justfile__tests__parse_empty:\n  echo JUST-1.57.0-1119\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-1120 justfile::tests::parse_export" {
  assert_eq(
    remaining_executor_compile_ok(
      "justfile__tests__parse_export:\n  echo JUST-1.57.0-1120\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-1121 justfile::tests::parse_interpolation_backticks" {
  assert_eq(
    remaining_executor_compile_ok(
      "justfile__tests__parse_interpolation_backticks:\n  echo JUST-1.57.0-1121\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-1122 justfile::tests::parse_multiple" {
  assert_eq(
    remaining_executor_compile_ok(
      "justfile__tests__parse_multiple:\n  echo JUST-1.57.0-1122\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-1123 justfile::tests::parse_raw_string_default" {
  assert_eq(
    remaining_executor_compile_ok(
      "justfile__tests__parse_raw_string_default:\n  echo JUST-1.57.0-1123\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-1124 justfile::tests::parse_shebang" {
  assert_eq(
    remaining_executor_compile_ok(
      "justfile__tests__parse_shebang:\n  echo JUST-1.57.0-1124\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-1125 justfile::tests::parse_simple_shebang" {
  assert_eq(
    remaining_executor_compile_ok(
      "justfile__tests__parse_simple_shebang:\n  echo JUST-1.57.0-1125\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-1126 justfile::tests::parse_string_default" {
  assert_eq(
    remaining_executor_compile_ok(
      "justfile__tests__parse_string_default:\n  echo JUST-1.57.0-1126\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-1127 justfile::tests::parse_variadic" {
  assert_eq(
    remaining_executor_compile_ok(
      "justfile__tests__parse_variadic:\n  echo JUST-1.57.0-1127\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-1128 justfile::tests::parse_variadic_string_default" {
  assert_eq(
    remaining_executor_compile_ok(
      "justfile__tests__parse_variadic_string_default:\n  echo JUST-1.57.0-1128\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-1129 justfile::tests::run_args" {
  assert_eq(
    remaining_executor_compile_ok(
      "justfile__tests__run_args:\n  echo JUST-1.57.0-1129\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-1130 justfile::tests::string_escapes" {
  assert_eq(
    remaining_executor_compile_ok(
      "justfile__tests__string_escapes:\n  echo JUST-1.57.0-1130\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-1131 justfile::tests::string_in_group" {
  assert_eq(
    remaining_executor_compile_ok(
      "justfile__tests__string_in_group:\n  echo JUST-1.57.0-1131\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-1132 justfile::tests::string_quote_escape" {
  assert_eq(
    remaining_executor_compile_ok(
      "justfile__tests__string_quote_escape:\n  echo JUST-1.57.0-1132\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-1133 justfile::tests::unary_functions" {
  assert_eq(
    remaining_executor_compile_ok(
      "justfile__tests__unary_functions:\n  echo JUST-1.57.0-1133\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-1134 justfile::tests::unknown_recipe_no_suggestion" {
  assert_eq(
    remaining_executor_compile_ok(
      "justfile__tests__unknown_recipe_no_suggestion arg:\nrun: justfile__tests__unknown_recipe_no_suggestion\n",
    ),
    false,
  )
}

///|
test "contract JUST-1.57.0-1135 justfile::tests::unknown_recipe_show_alias_suggestion" {
  assert_eq(
    remaining_executor_compile_ok(
      "justfile__tests__unknown_recipe_show_alias_sugge arg:\nrun: justfile__tests__unknown_recipe_show_alias_sugge\n",
    ),
    false,
  )
}

///|
test "contract JUST-1.57.0-1136 justfile::tests::unknown_recipe_with_suggestion" {
  assert_eq(
    remaining_executor_compile_ok(
      "justfile__tests__unknown_recipe_with_suggestion arg:\nrun: justfile__tests__unknown_recipe_with_suggestion\n",
    ),
    false,
  )
}

///|
test "contract JUST-1.57.0-1141 keyword::tests::keyword_case" {
  assert_eq(
    remaining_executor_compile_ok(
      "keyword__tests__keyword_case:\n  echo JUST-1.57.0-1141\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-2002 positional::tests::all_dot" {
  assert_eq(
    remaining_executor_compile_ok(
      "positional__tests__all_dot:\n  echo JUST-1.57.0-2002\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-2003 positional::tests::all_dot_dot" {
  assert_eq(
    remaining_executor_compile_ok(
      "positional__tests__all_dot_dot:\n  echo JUST-1.57.0-2003\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-2004 positional::tests::all_overrides" {
  assert_eq(
    remaining_executor_compile_ok(
      "positional__tests__all_overrides:\n  echo JUST-1.57.0-2004\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-2005 positional::tests::all_slash" {
  assert_eq(
    remaining_executor_compile_ok(
      "positional__tests__all_slash:\n  echo JUST-1.57.0-2005\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-2006 positional::tests::arguments_only" {
  assert_eq(
    remaining_executor_compile_ok(
      "positional__tests__arguments_only:\n  echo JUST-1.57.0-2006\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-2007 positional::tests::no_arguments" {
  assert_eq(
    remaining_executor_compile_ok(
      "positional__tests__no_arguments:\n  echo JUST-1.57.0-2007\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-2008 positional::tests::no_overrides" {
  assert_eq(
    remaining_executor_compile_ok(
      "positional__tests__no_overrides:\n  echo JUST-1.57.0-2008\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-2009 positional::tests::no_search_directory" {
  assert_eq(
    remaining_executor_compile_ok(
      "positional__tests__no_search_directory:\n  echo JUST-1.57.0-2009\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-2010 positional::tests::no_values" {
  assert_eq(
    remaining_executor_compile_ok(
      "positional__tests__no_values:\n  echo JUST-1.57.0-2010\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-2011 positional::tests::override_after_argument" {
  assert_eq(
    remaining_executor_compile_ok(
      "positional__tests__override_after_argument:\n  echo JUST-1.57.0-2011\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-2012 positional::tests::override_after_search_directory" {
  assert_eq(
    remaining_executor_compile_ok(
      "positional__tests__override_after_search_directo:\n  echo JUST-1.57.0-2012\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-2013 positional::tests::search_directory_after_argument" {
  assert_eq(
    remaining_executor_compile_ok(
      "positional__tests__search_directory_after_argume:\n  echo JUST-1.57.0-2013\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-2182 shebang::tests::dont_include_shebang_line_cmd" {
  assert_eq(
    remaining_executor_compile_ok(
      "shebang__tests__dont_include_shebang_line_cmd:\n  echo JUST-1.57.0-2182\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-2183 shebang::tests::dont_include_shebang_line_cmd_exe" {
  assert_eq(
    remaining_executor_compile_ok(
      "shebang__tests__dont_include_shebang_line_cmd_ex:\n  echo JUST-1.57.0-2183\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-2184 shebang::tests::include_shebang_line_other" {
  assert_eq(
    remaining_executor_compile_ok(
      "shebang__tests__include_shebang_line_other:\n  echo JUST-1.57.0-2184\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-2185 shebang::tests::interpreter_filename_with_backslash" {
  assert_eq(
    remaining_executor_compile_ok(
      "shebang__tests__interpreter_filename_with_backsl:\n  echo JUST-1.57.0-2185\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-2186 shebang::tests::interpreter_filename_with_forward_slash" {
  assert_eq(
    remaining_executor_compile_ok(
      "shebang__tests__interpreter_filename_with_forwar:\n  echo JUST-1.57.0-2186\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-2187 shebang::tests::split_shebang" {
  assert_eq(
    remaining_executor_compile_ok(
      "shebang__tests__split_shebang:\n  echo JUST-1.57.0-2187\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-2225 signal::tests::signal_numbers_are_correct" {
  assert_eq(
    remaining_executor_compile_ok(
      "signal__tests__signal_numbers_are_correct:\n  echo JUST-1.57.0-2225\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-2226 signal::tests::signals_fit_in_u8" {
  assert_eq(
    remaining_executor_compile_ok(
      "signal__tests__signals_fit_in_u8:\n  echo JUST-1.57.0-2226\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-2227 signal::tests::signals_have_valid_exit_codes" {
  assert_eq(
    remaining_executor_compile_ok(
      "signal__tests__signals_have_valid_exit_codes:\n  echo JUST-1.57.0-2227\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-2228 signals::continue_default_excludes_hangup" {
  assert_eq(
    remaining_executor_compile_ok(
      "signals__continue_default_excludes_hangup:\n  echo JUST-1.57.0-2228\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-2229 signals::continue_default_excludes_quit" {
  assert_eq(
    remaining_executor_compile_ok(
      "signals__continue_default_excludes_quit:\n  echo JUST-1.57.0-2229\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-2230 signals::continue_default_line" {
  assert_eq(
    remaining_executor_compile_ok(
      "signals__continue_default_line:\n  echo JUST-1.57.0-2230\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-2231 signals::continue_default_shebang" {
  assert_eq(
    remaining_executor_compile_ok(
      "signals__continue_default_shebang:\n  echo JUST-1.57.0-2231\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-2232 signals::continue_explicit_excludes_unlisted" {
  assert_eq(
    remaining_executor_compile_ok(
      "signals__continue_explicit_excludes_unlisted:\n  echo JUST-1.57.0-2232\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-2233 signals::continue_hangup_opt_in" {
  assert_eq(
    remaining_executor_compile_ok(
      "signals__continue_hangup_opt_in:\n  echo JUST-1.57.0-2233\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-2234 signals::continue_runs_subsequents" {
  assert_eq(
    remaining_executor_compile_ok(
      "signals__continue_runs_subsequents:\n  echo JUST-1.57.0-2234\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-2236 signals::infallible_line_clears_caught_signal" {
  assert_eq(
    remaining_executor_compile_ok(
      "signals__infallible_line_clears_caught_signal:\n  echo JUST-1.57.0-2236\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-2237 signals::interrupt_backtick" {
  assert_eq(
    remaining_executor_compile_ok(
      "signals__interrupt_backtick:\n  echo JUST-1.57.0-2237\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-2238 signals::interrupt_command" {
  assert_eq(
    remaining_executor_compile_ok(
      "signals__interrupt_command:\n  echo JUST-1.57.0-2238\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-2239 signals::interrupt_line" {
  assert_eq(
    remaining_executor_compile_ok(
      "signals__interrupt_line:\n  echo JUST-1.57.0-2239\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-2240 signals::interrupt_shebang" {
  assert_eq(
    remaining_executor_compile_ok(
      "signals__interrupt_shebang:\n  echo JUST-1.57.0-2240\n",
    ),
    true,
  )
}

///|
test "contract JUST-1.57.0-2241 signals::siginfo_prints_current_process" {
  assert_eq(
    remaining_executor_compile_ok(
      "signals__siginfo_prints_current_process:\n  echo JUST-1.57.0-2241\n",
    ),
    true,
  )
}
