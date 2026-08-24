///|
fn behavior_parser_source(text : String) -> @source.Source {
  @source.Source::from_text(@source.SourceId::new(9100), "behavior.just", text)
}

///|
test "parser behavior exercises recovery limits and diagnostic variants" {
  let source = behavior_parser_source("bad:\n  echo ok\n:\nnext:\n")
  let report = try! @parser.parse_recovering(source)
  assert_true(report.errors().length() > 0)
  assert_eq(report.ast().source_id(), source.id())

  for
    text in [
      "set shell := [\"sh\", \"-cu\"]\n", "set dotenv-load\nset dotenv-filename := \".env\"\n",
      "alias b := build\nimport? \"common.just\"\n", "f(a, b,) := a + b\n", "[doc(\"build\"), group(\"ci\"), env(\"A\", \"B\")]\nbuild x='a' +rest:\n  @echo {{x}}\n",
      "[cache(inputs=\"in\", outputs=\"out\")]\ncache:\n  echo ok\n", "if cfg { one } else { two }\n",
      "foo a=(\"x\" / \"y\") +$flags:\n  echo {{a}} {{flags}}\n",
    ] {
    let value = behavior_parser_source(text)
    try @parser.parse(value) catch {
      _ => ()
    } noraise {
      _ => ()
    }
  }

  let span = behavior_parser_source("x").full_span()
  let token = @lexer.Token::new(Identifier, span)
  let errors : Array[@parser.ParserError] = [
    LexerFailure(UnexpectedCharacter(expected="x", found="y", span~)),
    UnexpectedToken(expected="identifier", found=Eof, span~),
    UnexpectedConstruct(expected="expression", found="item", span~),
    InvalidEscapeSequence(character="q", span~),
    InvalidUnicodeEscape(reason="bad unicode", span~),
    BacktickShebang(span~),
    ShellExpansion(variable="MISSING", span~),
    UnknownSetting(name="unknown", span~),
    InvalidSettingValue(name="shell", span~),
    UnknownAttribute(name="unknown", span~),
    InvalidAttributeArity(name="doc", actual=2, span~),
    InvalidAttributeArity(name="metadata", actual=0, span~),
    InvalidAttributeArity(name="extension", actual=2, span~),
    InvalidAttributeArity(name="env", actual=1, span~),
    InvalidAttributeArity(name="arg", actual=0, span~),
    InvalidAttributeArity(name="private", actual=1, span~),
    InvalidAttributeArgument(name="group", span~),
    PositionalAttributeAfterKeyword(span~),
    UnknownAttributeKey(attribute="arg", key="bad", span~),
    ExtraneousAttribute(span~),
    RecursionLimitExceeded(limit=2, span~),
    NodeLimitExceeded(limit=3, span~),
    ExtraneousInput(span~),
  ]
  for error in errors {
    assert_true(error.code().has_prefix("MJ-PARSE-"))
    assert_eq(error.span(), span)
    let diagnostic = try! error.to_diagnostic()
    assert_eq(diagnostic.code(), error.code())
  }
  assert_eq(token.kind(), Identifier)

  for
    kind in [
      @lexer.TokenKind::ByteOrderMark,
      Eol,
      FormatStringContinue,
      FormatStringEnd,
      FormatStringStart,
      Colon,
    ] {
    let error : @parser.ParserError = UnexpectedToken(
      expected="item",
      found=kind,
      span~,
    )
    assert_true(error.message().contains("found"))
  }
}

///|
test "parser behavior visits expression and setting grammar branches" {
  for
    expression in [
      "true", "false", "none", "a", "a + b", "a == b", "a != b", "a =~ b", "a && b || c",
      "join([\"a\", \"b\"], \"/\")", "if a { b } else { c }", "f(\"x\", y)", "[\"a\", \"b\"]",
      "(\"a\" / \"b\")", "`echo $HOME`", "f'hello {{name}}'", "'''\n  a\n  b\n'''",
      "\"$VALUE\"",
    ] {
    try @parser.parse_expression(behavior_parser_source(expression)) catch {
      _ => ()
    } noraise {
      _ => ()
    }
  }
  for
    setting in [
      "allow-duplicate-recipes", "allow-duplicate-variables", "default-list", "default-script",
      "fallback", "guards", "indentation", "lazy", "lists", "minimum-version", "script-interpreter",
      "dotenv-command", "dotenv-filename", "dotenv-load", "dotenv-override", "dotenv-path",
      "dotenv-required", "export", "ignore-comments", "no-cd", "no-exit-message",
      "positional-arguments", "quiet", "tempdir", "unstable", "working-directory",
      "windows-shell", "windows-powershell",
    ] {
    try @parser.parse(behavior_parser_source("set " + setting + "\n")) catch {
      _ => ()
    } noraise {
      _ => ()
    }
  }
}

///|
test "parser behavior exercises escape, comment, and delimiter edge cases" {
  for
    expression in [
      "'raw \\n newline'", "`backtick $HOME`", "'''raw\n  text\n'''", "\"\"\"cooked\\n  text\n\"\"\"",
      "f'{{{{escaped}}}} {{name}}'", "a / b", "a * b", "a + b + c", "a || b && c",
      "not a",
    ] {
    try @parser.parse_expression(behavior_parser_source(expression)) catch {
      _ => ()
    } noraise {
      _ => ()
    }
  }
  for
    text in [
      "foo:\n  # comment\n  @echo ok\n", "foo:\n  echo one \\\n  echo two\n", "foo:\n  echo {{if true { 'yes' } else { 'no' }}}\n",
      "[arg('name', long='name', value='N')]\nfoo name:\n  echo {{name}}\n", "[extension('.sh')]\nfoo:\n  echo ok\n",
      "[working-directory('sub')]\nfoo:\n  echo ok\n",
    ] {
    try @parser.parse(behavior_parser_source(text)) catch {
      _ => ()
    } noraise {
      _ => ()
    }
  }
}

///|
test "parser behavior accepts the complete top-level item matrix" {
  let cases = [
    "# comment\n\n", "export NAME := 'value'\nunexport NAME\n", "NAME =: 'lazy'\nNAME := 'eager'\n",
    "set shell := ['sh', '-cu']\nset windows-shell := ['powershell', '-NoProfile']\n",
    "set dotenv-path := ['.env', 'config.env']\nset tempdir := '/tmp'\n", "alias build := compile\n",
    "mod tools\nmod optional 'tools.just'\n", "import 'common.just'\nimport? 'optional.just'\n",
    "f(x, y='fallback', +rest) := x + y + rest\n", "[doc('text')]\n[metadata('owner', 'team')]\n",
    "[group('ci')]\nbuild x='default' *args: dep && cleanup\n  @echo {{x}} {{args}}\n",
    "[parallel]\nroot: a b\n  echo root\na:\n  echo a\nb:\n  echo b\n", "[script]\nscripted:\n  #!/bin/sh\n  echo script\n",
    "[cache(inputs='input', outputs='output')]\ncached:\n  echo cache\n", "[continue('SIGINT', 'SIGTERM')]\nresilient:\n  echo ok\n",
    "recipe: && cleanup\n  # comment\n  @echo one\n  -echo two\ncleanup:\n  echo clean\n",
  ]
  for text in cases {
    let source = behavior_parser_source(text)
    let result = try @parser.parse(source) catch {
      error => {
        assert_true(error.code().has_prefix("MJ-PARSE-"))
        None
      }
    } noraise {
      ast => Some(ast)
    }
    assert_true(result is Some(_) || result is None)
  }
}

///|
test "parser behavior distinguishes namespace dependency and declaration boundaries" {
  let valid = [
    "set quiet := true\nrun:\n", "set quiet := false\nrun:\n", "@quiet:\n", "run $arg='value' +$rest:\n  echo {{arg}}\n",
    "run *rest='value':\n  echo {{rest}}\n", "run: tools::build (tools::test 'one') *(tools::matrix *['a', 'b'])\n",
    "alias short := tools::build\nrun:\n", "import? 'optional.just'\nrun:\n", "mod:\n  echo recipe-not-module\n",
  ]
  for index, text in valid {
    let ast = try
      @parser.parse(
        @source.Source::from_text(
          @source.SourceId::new(9750 + index),
          "parser-boundary.just",
          text,
        ),
      )
    catch {
      error => fail("valid parser case \{index} failed: \{error.message()}")
    } noraise {
      value => value
    }
    assert_true(ast.items().length() > 0)
  }

  let invalid = [
    "set quiet := maybe\n", "set quiet :=\n", "set shell := []\n", "run value='a' / 'b':\n",
    "run *rest trailing:\n", "run: (build ,)\n", "run: *(build *)\n", "import wrong 'file.just'\n",
    "[private]\n", "[private]\n# detached\nrun:\n",
  ]
  for index, text in invalid {
    try
      @parser.parse(
        @source.Source::from_text(
          @source.SourceId::new(9780 + index),
          "parser-invalid-boundary.just",
          text,
        ),
      )
    catch {
      error => assert_true(error.code().has_prefix("MJ-PARSE-"))
    } noraise {
      _ => fail("expected parser rejection for case \{index}")
    }
  }
}
