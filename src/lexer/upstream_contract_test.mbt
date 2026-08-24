///|
fn contract_source(text : String) -> @source.Source {
  @source.Source::from_text(
    @source.SourceId::new(1800),
    "upstream-contract",
    text,
  )
}

///|
fn assert_contract(
  text : String,
  expect_error : Bool,
  expected_offset : Int,
  expected_width : Int,
) -> Unit raise {
  if !expect_error {
    let _ = lex(contract_source(text))
  } else {
    try lex(contract_source(text)) catch {
      error => {
        assert_eq(error.span().start_byte(), expected_offset)
        assert_eq(error.span().length(), expected_width)
      }
    } noraise {
      _ => fail("upstream lexer contract unexpectedly succeeded")
    }
  }
}

///|
test "contract JUST-1.57.0-1161 lexer::tests::ampersand_ampersand" {
  assert_contract("&&", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1162 lexer::tests::ampersand_eof" {
  assert_contract("&", true, 1, 0)
}

///|
test "contract JUST-1.57.0-1163 lexer::tests::ampersand_unexpected" {
  assert_contract("&%", true, 1, 1)
}

///|
test "contract JUST-1.57.0-1164 lexer::tests::backtick" {
  assert_contract("`echo`", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1165 lexer::tests::backtick_multi_line" {
  assert_contract("`echo\necho`", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1166 lexer::tests::bad_dedent" {
  assert_contract("a\n foo\n   bar\n  baz", true, 14, 2)
}

///|
test "contract JUST-1.57.0-1167 lexer::tests::bang" {
  assert_contract("!", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1168 lexer::tests::bang_equals" {
  assert_contract("!=", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1169 lexer::tests::brace_escape" {
  assert_contract("foo:\n  {{{{\n", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1170 lexer::tests::brace_l" {
  assert_contract("{", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1171 lexer::tests::brace_lll" {
  assert_contract("{{{", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1172 lexer::tests::brace_r" {
  assert_contract("{}", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1173 lexer::tests::brace_rrr" {
  assert_contract("{{{}}}", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1174 lexer::tests::brackets" {
  assert_contract("[][]", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1175 lexer::tests::comment" {
  assert_contract("# hello", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1176 lexer::tests::cooked_multiline_string" {
  assert_contract("\"\"\"hello\ngoodbye\"\"\"", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1177 lexer::tests::cooked_string" {
  assert_contract("\"hello\"", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1178 lexer::tests::cooked_string_multi_line" {
  assert_contract("\"hello\ngoodbye\"", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1179 lexer::tests::crlf_newline" {
  assert_contract("#\r\n#asdf\r\n", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1180 lexer::tests::dollar" {
  assert_contract("$", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1181 lexer::tests::eol_carriage_return_linefeed" {
  assert_contract("\r\n", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1182 lexer::tests::eol_linefeed" {
  assert_contract("\n", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1183 lexer::tests::equals" {
  assert_contract("=", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1184 lexer::tests::equals_equals" {
  assert_contract("==", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1185 lexer::tests::export_complex" {
  assert_contract("export foo = ('foo' + 'bar') + `baz`", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1186 lexer::tests::export_concatenation" {
  assert_contract("export foo = 'foo' + 'bar'", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1187 lexer::tests::format_string_continue" {
  assert_contract("f'{{foo}}bar{{baz}}'", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1188 lexer::tests::format_string_empty" {
  assert_contract("f''", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1189 lexer::tests::format_string_followed_by_recipe" {
  assert_contract("foo := f'{{'foo'}}{{'bar'}}'\nbar:", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1190 lexer::tests::format_string_identifier" {
  assert_contract("f'{{foo}}'", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1191 lexer::tests::format_string_whitespace" {
  assert_contract("f '{{foo}}'", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1192 lexer::tests::format_string_wrong_identifier" {
  assert_contract("g'{{foo}}'", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1193 lexer::tests::indent_indent_dedent_indent" {
  assert_contract("a\n  b\n    c\n  d\n    e\n", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1194 lexer::tests::indent_recipe_dedent_indent" {
  assert_contract("a\n  b:\n    c\n  d\n    e\n", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1195 lexer::tests::indented_block" {
  assert_contract("foo:\n  a\n  b\n  c\n", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1196 lexer::tests::indented_block_followed_by_blank" {
  assert_contract("foo:\n    a\n\nb:\n", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1197 lexer::tests::indented_block_followed_by_item" {
  assert_contract("foo:\n  a\nb:\n", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1198 lexer::tests::indented_blocks" {
  assert_contract(
    "b: a\n  @mv a b\n\na:\n  @touch F\n  @touch a\n\nd: c\n  @rm c\n\nc: b\n  @mv b c\n",
    false, -1, -1,
  )
}

///|
test "contract JUST-1.57.0-1199 lexer::tests::indented_format_string_followed_by_recipe" {
  assert_contract("foo := f'''{{'foo'}}{{'bar'}}'''\nbar:", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1200 lexer::tests::indented_line" {
  assert_contract("foo:\n a", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1201 lexer::tests::indented_line_containing_unpaired_carriage_return" {
  assert_contract("foo:\n \r \n", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1202 lexer::tests::indented_normal" {
  assert_contract("a\n  b\n  c\n", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1203 lexer::tests::indented_normal_multiple" {
  assert_contract("a\n  b\n    c\n", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1204 lexer::tests::indented_normal_nonempty_blank" {
  assert_contract("a\n  b\n\t\t\n  c\n", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1205 lexer::tests::interpolation_empty" {
  assert_contract("hello:\n echo {{}}", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1206 lexer::tests::interpolation_expression" {
  assert_contract(
    "hello:\n echo {{`echo hello` + `echo goodbye`}}", false, -1, -1,
  )
}

///|
test "contract JUST-1.57.0-1207 lexer::tests::interpolation_raw_multiline_string" {
  assert_contract("hello:\n echo {{'\n'}}", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1208 lexer::tests::invalid_name_start_dash" {
  assert_contract("-foo", true, 0, 1)
}

///|
test "contract JUST-1.57.0-1209 lexer::tests::invalid_name_start_digit" {
  assert_contract("0foo", true, 0, 1)
}

///|
test "contract JUST-1.57.0-1210 lexer::tests::mismatched_closing_brace" {
  assert_contract("(]", true, 1, 0)
}

///|
test "contract JUST-1.57.0-1211 lexer::tests::mixed_leading_whitespace_indent" {
  assert_contract("a\n foo\n \tbar", true, 7, 2)
}

///|
test "contract JUST-1.57.0-1212 lexer::tests::mixed_leading_whitespace_normal" {
  assert_contract("a\n\t echo hello", true, 2, 2)
}

///|
test "contract JUST-1.57.0-1213 lexer::tests::mixed_leading_whitespace_recipe" {
  assert_contract("a:\n\t echo hello", true, 3, 2)
}

///|
test "contract JUST-1.57.0-1214 lexer::tests::multiple_recipes" {
  assert_contract("a:\n  foo\nb:", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1215 lexer::tests::name_new" {
  assert_contract("foo", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1216 lexer::tests::open_delimiter_eol" {
  assert_contract("[\n](\n){\n}", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1217 lexer::tests::plus_plus" {
  assert_contract("++", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1219 lexer::tests::raw_string" {
  assert_contract("'hello'", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1220 lexer::tests::raw_string_multi_line" {
  assert_contract("'hello\ngoodbye'", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1221 lexer::tests::tokenize_assignment_backticks" {
  assert_contract("a = `echo hello` + `echo goodbye`", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1222 lexer::tests::tokenize_comment" {
  assert_contract("a:=#", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1223 lexer::tests::tokenize_comment_before_variable" {
  assert_contract("#\nA='1'\necho:\n  echo {{A}}\n", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1224 lexer::tests::tokenize_comment_with_bang" {
  assert_contract("a:=#foo!", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1225 lexer::tests::tokenize_continued_indent" {
  assert_contract("hello:\n  foo\n\n  bar\n\nbaz\n", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1226 lexer::tests::tokenize_empty_interpolation" {
  assert_contract("hello:\n echo {{}}", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1227 lexer::tests::tokenize_empty_lines" {
  assert_contract(
    "\n# this does something\nhello:\n  asdf\n  bsdf\n\n  csdf\n\n  dsdf # whatever\n\n# yolo\n",
    false, -1, -1,
  )
}

///|
test "contract JUST-1.57.0-1228 lexer::tests::tokenize_indented_block" {
  assert_contract("foo:\n  a\n  b\n  c\n", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1229 lexer::tests::tokenize_indented_line" {
  assert_contract("foo:\n a", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1230 lexer::tests::tokenize_interpolation_backticks" {
  assert_contract(
    "hello:\n echo {{`echo hello` + `echo goodbye`}}", false, -1, -1,
  )
}

///|
test "contract JUST-1.57.0-1231 lexer::tests::tokenize_junk" {
  assert_contract(
    "bob\n\nhello blah blah blah : a b c #whatever\n", false, -1, -1,
  )
}

///|
test "contract JUST-1.57.0-1232 lexer::tests::tokenize_multiple" {
  assert_contract(
    "\nhello:\n  a\n  b\n\n  c\n\n  d\n\n# hello\nbob:\n  frank\n\n", false, -1,
    -1,
  )
}

///|
test "contract JUST-1.57.0-1233 lexer::tests::tokenize_names" {
  assert_contract("foo\nbar-bob\nb-bob_asdfAAAA\ntest123\n", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1234 lexer::tests::tokenize_order" {
  assert_contract(
    "b: a\n  @mv a b\n\na:\n  @touch F\n  @touch a\n\nd: c\n  @rm c\n\nc: b\n  @mv b c\n",
    false, -1, -1,
  )
}

///|
test "contract JUST-1.57.0-1235 lexer::tests::tokenize_parens" {
  assert_contract("((())) ()abc(+", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1236 lexer::tests::tokenize_recipe_after_body" {
  assert_contract("foo:\n echo FOO\n\nfoo:", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1237 lexer::tests::tokenize_recipe_complex_interpolation_expression" {
  assert_contract("foo: #lol\n {{a + b + \"z\" + blarg}}", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1238 lexer::tests::tokenize_recipe_interpolation_eof" {
  assert_contract(
    "foo: # more comments\n {{hello}}\n# another comment\n", false, -1, -1,
  )
}

///|
test "contract JUST-1.57.0-1239 lexer::tests::tokenize_recipe_interpolation_eol" {
  assert_contract("foo: # some comment\n {{hello}}\n", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1240 lexer::tests::tokenize_recipe_multiple_interpolations" {
  assert_contract("foo:,#ok\n {{a}}0{{b}}1{{c}}", false, -1, -1)
}

///|
test "contract JUST-1.57.0-1241 lexer::tests::tokenize_space_then_tab" {
  assert_contract("a:\n 0\n 1\n\t2\n", true, 9, 1)
}

///|
test "contract JUST-1.57.0-1242 lexer::tests::tokenize_strings" {
  assert_contract(
    "a = \"'a'\" + '\"b\"' + \"'c'\" + '\"d\"'#echo hello", false, -1, -1,
  )
}

///|
test "contract JUST-1.57.0-1243 lexer::tests::tokenize_tabs_then_tab_space" {
  assert_contract("a:\n\t\t0\n\t\t 1\n\t  2\n", true, 12, 2)
}

///|
test "contract JUST-1.57.0-1244 lexer::tests::tokenize_unknown" {
  assert_contract("%", true, 0, 1)
}

///|
test "contract JUST-1.57.0-1245 lexer::tests::unclosed_interpolation_delimiter" {
  assert_contract("a:\n echo {{ foo", true, 9, 2)
}

///|
test "contract JUST-1.57.0-1246 lexer::tests::unclosed_parenthesis_in_interpolation" {
  assert_contract("a:\n echo {{foo(}}", true, 15, 0)
}

///|
test "contract JUST-1.57.0-1247 lexer::tests::unexpected_character_after_at" {
  assert_contract("@%", true, 1, 1)
}

///|
test "contract JUST-1.57.0-1248 lexer::tests::unpaired_carriage_return" {
  assert_contract("foo\rbar", true, 3, 1)
}

///|
test "contract JUST-1.57.0-1249 lexer::tests::unterminated_backtick" {
  assert_contract("`echo", true, 0, 1)
}

///|
test "contract JUST-1.57.0-1250 lexer::tests::unterminated_interpolation" {
  assert_contract("foo:\n echo {{\n  ", true, 11, 2)
}

///|
test "contract JUST-1.57.0-1251 lexer::tests::unterminated_raw_string" {
  assert_contract("r a='asdf", true, 4, 1)
}

///|
test "contract JUST-1.57.0-1252 lexer::tests::unterminated_string" {
  assert_contract("a = \"", true, 4, 1)
}

///|
test "contract JUST-1.57.0-1253 lexer::tests::unterminated_string_with_escapes" {
  assert_contract("a = \"\\n\\t\\r\\\"\\\\", true, 4, 1)
}
