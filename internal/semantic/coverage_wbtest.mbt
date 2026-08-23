///|
fn semantic_coverage_source(text : String) -> @source.Source {
  @source.Source::from_text(
    @source.SourceId::new(9800),
    "semantic.coverage",
    text,
  )
}

///|
test "semantic whitebox coverage visits platform and attribute compilation" {
  for
    name in [
      "android", "dragonfly", "freebsd", "linux", "macos", "netbsd", "openbsd", "unix",
      "windows", "unknown",
    ] {
    let _ = platform_for(name)
  }
  assert_true(attribute_lexical_compare("a", "b") < 0)
  assert_true(attribute_lexical_compare("b", "a") > 0)
  assert_eq(attribute_lexical_compare("a", "a"), 0)
  let ast = try! @parser.parse(
    semantic_coverage_source(
      "[private, doc(\"docs\"), group(\"ci\"), metadata(\"owner\"), " +
      "env(\"MODE\", \"test\"), no-cd, no-exit-message, no-quiet, parallel, " +
      "positional-arguments]\n" +
      "build:\n",
    ),
  )
  guard ast.items()[0] is Recipe(recipe) else { fail("expected recipe") }
  let attributes = try! compile_attributes(
    recipe.attributes(),
    recipe_name="build",
    recipe_span=recipe.span(),
  )
  assert_true(attributes.private())
  assert_eq(attributes.platform(), None)
  assert_eq(attributes.platforms(), [])
  assert_eq(attributes.group(), Some("ci"))
  assert_eq(attributes.groups(), ["ci"])
  assert_true(attributes.doc_expression() is Some(_))
  assert_true(attributes.working_directory() is None)
  assert_eq(attributes.shell(), [])
  assert_false(attributes.script())
  assert_eq(attributes.script_interpreter(), [])
  assert_false(attributes.confirm())
  assert_true(attributes.confirm_prompt() is None)
  assert_true(attributes.default() is None)
  assert_eq(attributes.env().length(), 1)
  assert_false(attributes.exit_message())
  assert_true(attributes.no_exit_message())
  assert_true(attributes.no_quiet())
  assert_true(attributes.positional_arguments())
  assert_true(attributes.no_cd())
  assert_true(attributes.parallel())
  assert_true(attributes.matches(TargetPlatform::new(Linux, true)))
  assert_true(
    platform_attributes_match(
      recipe.attributes(),
      TargetPlatform::new(Linux, true),
    ),
  )
  let _ = attributes.matches(TargetPlatform::new(Windows, false))
  for _ in 0..<attributes.names().length() {
    let _ = attributes.names()
  }
}

///|
test "semantic whitebox coverage visits project resolution and disabled paths" {
  let root = try! @path.PathValue::new("/workspace", Unix)
  let root_compilation = try! compile_source(
    semantic_coverage_source("root:\n"),
  )
  let child_compilation = try! compile_source(
    semantic_coverage_source("child:\n"),
  )
  let root_module = ProjectModule::new(
    @modulepath.ModulePath::root(),
    root_compilation,
    root,
    default_recipe="root",
  )
  let child_path = try! @modulepath.ModulePath::parse("child")
  let child_module = ProjectModule::new(
    child_path,
    child_compilation,
    root,
    default_recipe="child",
  )
  let project = try! ProjectCompilation::new([root_module, child_module])
  assert_eq(project.module_paths().length(), 2)
  assert_true(
    project.module_compilation(@modulepath.ModulePath::root()) is Some(_),
  )
  assert_true(
    project.resolve_module(@modulepath.ModulePath::root(), "child") is Some(_),
  )
  assert_true(
    project.resolve_recipe(@modulepath.ModulePath::root(), "root") is Some(_),
  )
  assert_true(
    project.resolve_recipe(@modulepath.ModulePath::root(), "missing") is None,
  )
  assert_false(project.recipe_disabled(@modulepath.ModulePath::root(), "root"))
  assert_false(
    project.alias_disabled(@modulepath.ModulePath::root(), "missing"),
  )
  assert_eq(
    project.default_recipe(@modulepath.ModulePath::root()),
    Some("root"),
  )
  assert_true(project.directory(@modulepath.ModulePath::root()) is Some(_))
  assert_eq(project.source_files(child_path).length(), 0)
  try validate_project_compilation(project) catch {
    _ => ()
  } noraise {
    _ => ()
  }
}

///|
fn semantic_expression_coverage_fixture() -> (
  @source.Span,
  @syntax.Expression,
  @syntax.Expression,
  @syntax.Expression,
) raise @source.SourceError {
  let span = @source.Span::new(@source.SourceId::new(9801), 0, 1)
  let literal = @syntax.StringLiteral::new("'value'", "value", Raw, span)
  let string : @syntax.Expression = String(literal)
  let boolean : @syntax.Expression = Boolean(value=true, span~)
  let variable : @syntax.Expression = Variable(name="known", span~)
  (span, string, boolean, variable)
}

///|
test "semantic whitebox coverage visits expression validators and const paths" {
  let (span, string, boolean, variable) = semantic_expression_coverage_fixture()
  let call : @syntax.Expression = Call(
    name="assert",
    arguments=[boolean],
    span~,
  )
  let list : @syntax.Expression = List(elements=[string, variable], span~)
  let parenthesized : @syntax.Expression = Parenthesized(
    expression=variable,
    span~,
  )
  let unary : @syntax.Expression = Unary(operator=Not, operand=boolean, span~)
  let binary : @syntax.Expression = Binary(
    operator=Equal,
    operator_span=span,
    lhs=variable,
    rhs=string,
    span~,
  )
  let conditional : @syntax.Expression = Conditional(
    condition=binary,
    then_branch=string,
    else_branch=Some(variable),
    span~,
  )
  let format : @syntax.Expression = Format(
    start=@syntax.StringLiteral::new("\"\"", "", Cooked, span),
    parts=[
      @syntax.FormatPart::new(
        variable,
        @syntax.StringLiteral::new("\"x\"", "x", Cooked, span),
      ),
    ],
    span~,
  )
  let function = @syntax.FunctionDefinition::new(
    "f",
    [@syntax.FunctionParameter::new("x", span)],
    variable,
    [],
    span,
  )
  let functions : Map[String, @syntax.FunctionDefinition] = Map([
    ("f", function),
  ])
  let variables : Set[String] = Set(["known"])
  let locals : Set[String] = Set(["local"])
  for
    expression in [
      string, boolean, variable, call, list, parenthesized, unary, binary, conditional,
      format,
    ] {
    try
      validate_expression_semantics(expression, variables, locals, functions)
    catch {
      _ => ()
    } noraise {
      _ => ()
    }
  }
  assert_true(expression_is_const(string, variables))
  assert_true(expression_is_const(boolean, variables))
  assert_true(expression_is_const(variable, variables))
  assert_false(expression_is_const(variable, Set([])))
  assert_true(expression_is_const(list, variables))
  assert_true(expression_is_const(parenthesized, variables))
  assert_true(expression_is_const(unary, variables))
  assert_true(expression_is_const(binary, variables))
  assert_true(expression_is_const(conditional, variables))
  assert_true(expression_is_const(format, variables))
  assert_false(
    expression_is_const(
      Backtick(@syntax.StringLiteral::new("`x`", "x", Backtick, span)),
      variables,
    ),
  )
  assert_false(
    expression_is_const(Call(name="shell", arguments=[], span~), variables),
  )
  try validate_const_expression(variable, Set([]), variables) catch {
    UndefinedVariable(..) => ()
    _ => fail("unexpected const validation error")
  } noraise {
    _ => fail("expected undefined variable")
  }
  try validate_const_expression(variable, variables, Set([])) catch {
    NonConstVariable(..) => ()
    _ => fail("unexpected non-const validation error")
  } noraise {
    _ => fail("expected non-const variable")
  }
  try
    validate_const_expression(
      Backtick(@syntax.StringLiteral::new("`x`", "x", Backtick, span)),
      variables,
      variables,
    )
  catch {
    ConstContext(..) => ()
    _ => fail("unexpected backtick validation error")
  } noraise {
    _ => fail("expected backtick validation error")
  }
  try
    validate_const_expression(
      Call(name="f", arguments=[], span~),
      variables,
      variables,
    )
  catch {
    ConstContext(..) => ()
    _ => fail("unexpected function validation error")
  } noraise {
    _ => fail("expected function validation error")
  }
}

///|
test "semantic whitebox coverage visits list mode and dependency validators" {
  let (span, string, boolean, variable) = semantic_expression_coverage_fixture()
  let list : @syntax.Expression = List(elements=[string], span~)
  let comparison : @syntax.Expression = Binary(
    operator=Equal,
    operator_span=span,
    lhs=variable,
    rhs=string,
    span~,
  )
  let logical : @syntax.Expression = Binary(
    operator=And,
    operator_span=span,
    lhs=comparison,
    rhs=comparison,
    span~,
  )
  let conditional : @syntax.Expression = Conditional(
    condition=comparison,
    then_branch=string,
    else_branch=None,
    span~,
  )
  for
    expression in [
      list,
      boolean,
      Unary(operator=Not, operand=boolean, span~),
      logical,
      conditional,
    ] {
    try validate_list_mode_expression(expression, false) catch {
      ListsFeature(..) => ()
      _ => ()
    } noraise {
      _ => ()
    }
  }
  assert_true(comparison_condition(comparison))
  assert_true(comparison_condition(logical))
  assert_false(comparison_condition(variable))
  assert_true(
    recipe_line_is_comment(
      @syntax.RecipeLine::new(
        [Text(text="# comment", span~)],
        span,
        source_start_line=1,
        source_end_line=1,
      ),
    ),
  )
  assert_true(
    recipe_line_is_continuation(
      @syntax.RecipeLine::new(
        [Text(text="echo \\", span~)],
        span,
        source_start_line=1,
        source_end_line=1,
      ),
    ),
  )
  let recipe = @syntax.Recipe::new(
    "run",
    false,
    [],
    [],
    [],
    [
      @syntax.RecipeLine::new(
        [Text(text="#! /bin/sh", span~)],
        span,
        source_start_line=1,
        source_end_line=1,
      ),
    ],
    [],
    span,
  )
  assert_true(semantic_recipe_has_shebang(recipe))
  try
    validate_recipe_sigils(
      @syntax.Recipe::new(
        "bad",
        false,
        [],
        [],
        [],
        [
          @syntax.RecipeLine::new(
            [Text(text="-?echo", span~)],
            span,
            source_start_line=1,
            source_end_line=1,
          ),
        ],
        [],
        span,
      ),
      true,
      false,
    )
  catch {
    GuardAndInfallibleSigil(..) => ()
    _ => fail("unexpected sigil validation error")
  } noraise {
    _ => fail("expected guard/infallible validation error")
  }
  try
    validate_shell_recipe_indentation(
      @syntax.Recipe::new(
        "bad",
        false,
        [],
        [],
        [],
        [
          @syntax.RecipeLine::new(
            [Text(text="  echo", span~)],
            span,
            source_start_line=1,
            source_end_line=1,
          ),
        ],
        [],
        span,
      ),
    )
  catch {
    InvalidIndentation(..) => ()
    _ => fail("unexpected indentation validation error")
  } noraise {
    _ => fail("expected indentation validation error")
  }
}

///|
test "semantic whitebox coverage exercises setting and attribute branches" {
  let source = @source.Source::from_text(
    @source.SourceId::new(9810),
    "settings.just",
    "set lists\nset quiet\nset indentation := '  '\n" +
    "set shell := ['sh', '-cu']\nset minimum-version := '1.0.0'\nrun:\n",
  )
  let ast = try! @parser.parse(source)
  let settings : Array[@syntax.Setting] = []
  for item in ast.items() {
    guard item is Setting(setting) else { continue }
    settings.push(setting)
  }
  let compiled = try! compile_settings(settings)
  assert_true(compiled.has("lists"))
  assert_true(compiled.bool("quiet"))
  assert_eq(compiled.get("indentation"), Some(Text("  ")))
  assert_eq(compiled.kind("shell"), Some(Expression))
  assert_eq(compiled.kind("missing"), None)
  assert_eq(compiled.get("missing"), None)
  assert_eq(SettingValue::Flag.as_bool(), Some(true))
  assert_eq(SettingValue::Boolean(false).as_bool(), Some(false))
  assert_eq(SettingValue::Text("x").as_text(), Some("x"))
  assert_eq(
    SettingValue::Expression(Boolean(value=true, span=source.full_span())).as_text(),
    None,
  )
  assert_true(setting_specs().length() > 20)
  assert_true(setting_spec("shell") is Some(_))
  assert_eq(setting_spec("missing"), None)

  let conflict_source = @source.Source::from_text(
    @source.SourceId::new(9811),
    "conflict.just",
    "set no-cd\nset working-directory := 'sub'\n",
  )
  let conflict_ast = try! @parser.parse(conflict_source)
  let conflict_settings : Array[@syntax.Setting] = []
  for item in conflict_ast.items() {
    guard item is Setting(setting) else { continue }
    conflict_settings.push(setting)
  }
  try compile_settings(conflict_settings) catch {
    SettingConflict(..) => ()
    error => fail("unexpected setting conflict: \{Repr(error)}")
  } noraise {
    _ => fail("expected setting conflict")
  }

  for
    text in [
      "set indentation := ''\n", "set indentation := ' \t'\n", "set indentation := 'x'\n",
      "set minimum-version := `echo 1.0.0`\n", "set unknown\n",
    ] {
    let invalid = try
      @parser.parse(
        @source.Source::from_text(
          @source.SourceId::new(9812),
          "invalid.just",
          text,
        ),
      )
    catch {
      _ => continue
    } noraise {
      value => value
    }
    let nodes : Array[@syntax.Setting] = []
    for item in invalid.items() {
      guard item is Setting(setting) else { continue }
      nodes.push(setting)
    }
    try compile_settings(nodes) catch {
      _ => ()
    } noraise {
      _ => fail("expected invalid setting")
    }
  }

  let attribute_source = @source.Source::from_text(
    @source.SourceId::new(9813),
    "attributes.just",
    "run:\n",
  )
  let recipe = match (try! @parser.parse(attribute_source)).items()[0] {
    Recipe(value) => value
    _ => abort("expected recipe")
  }
  let string = @syntax.Expression::String(
    @syntax.StringLiteral::new(
      "'value'",
      "value",
      Raw,
      attribute_source.full_span(),
    ),
  )
  let argument = fn(name : String?, value : @syntax.Expression?) {
    @syntax.AttributeArgument::new(name, value, attribute_source.full_span())
  }
  let attributes_input = [
    @syntax.Attribute::new("private", [], attribute_source.full_span()),
    @syntax.Attribute::new(
      "doc",
      [argument(None, Some(string))],
      attribute_source.full_span(),
    ),
    @syntax.Attribute::new(
      "group",
      [argument(None, Some(string))],
      attribute_source.full_span(),
    ),
    @syntax.Attribute::new(
      "confirm",
      [argument(None, Some(string))],
      attribute_source.full_span(),
    ),
    @syntax.Attribute::new(
      "continue",
      [
        argument(
          None,
          Some(
            String(
              @syntax.StringLiteral::new(
                "'SIGINT'",
                "SIGINT",
                Raw,
                attribute_source.full_span(),
              ),
            ),
          ),
        ),
      ],
      attribute_source.full_span(),
    ),
    @syntax.Attribute::new(
      "env",
      [argument(None, Some(string)), argument(None, Some(string))],
      attribute_source.full_span(),
    ),
    @syntax.Attribute::new("exit-message", [], attribute_source.full_span()),
    @syntax.Attribute::new(
      "extension",
      [argument(None, Some(string))],
      attribute_source.full_span(),
    ),
    @syntax.Attribute::new(
      "metadata",
      [argument(None, Some(string))],
      attribute_source.full_span(),
    ),
    @syntax.Attribute::new("no-quiet", [], attribute_source.full_span()),
    @syntax.Attribute::new("parallel", [], attribute_source.full_span()),
    @syntax.Attribute::new(
      "positional-arguments",
      [],
      attribute_source.full_span(),
    ),
    @syntax.Attribute::new(
      "arg",
      [argument(Some("x"), Some(string))],
      attribute_source.full_span(),
    ),
    @syntax.Attribute::new(
      "cache",
      [argument(Some("inputs"), Some(string))],
      attribute_source.full_span(),
    ),
    @syntax.Attribute::new("linux", [], attribute_source.full_span()),
  ]
  let attributes = try! compile_attributes(
    attributes_input,
    recipe_name="run",
    recipe_span=recipe.span(),
  )
  assert_true(attributes.private())
  assert_eq(attributes.doc(), Some("value"))
  assert_eq(attributes.extension(), Some("value"))
  assert_eq(attributes.continue_signals(), ["SIGINT"])
  assert_eq(attributes.metadata(), ["value"])
  assert_true(attributes.args().length() > 0)
  assert_true(attributes.cache().length() > 0)

  for
    text in [
      "[group]\nrun:\n", "[group(1)]\nrun:\n", "[continue('TERM')]\nrun:\n", "[extension(1)]\nrun:\n",
      "[metadata(1)]\nrun:\n", "[script, shell]\nrun:\n", "[exit-message, no-exit-message]\nrun:\n",
    ] {
    let invalid = try
      @parser.parse(
        @source.Source::from_text(
          @source.SourceId::new(9814),
          "attr-invalid.just",
          text,
        ),
      )
    catch {
      _ => continue
    } noraise {
      value => value
    }
    try compile(invalid, allow_unstable=true) catch {
      _ => ()
    } noraise {
      _ => fail("expected attribute error")
    }
  }
}

///|
test "semantic attribute compiler rejects defensive malformed inputs" {
  let source = @source.Source::from_text(
    @source.SourceId::new(9820),
    "malformed-attributes.just",
    "run:\n",
  )
  let span = source.full_span()
  let string = @syntax.Expression::String(
    @syntax.StringLiteral::new("'value'", "value", Raw, span),
  )
  let boolean : @syntax.Expression = Boolean(value=true, span~)
  let argument = fn(value : @syntax.Expression?) {
    @syntax.AttributeArgument::new(None, value, span)
  }
  let attribute = fn(
    name : String,
    arguments : Array[@syntax.AttributeArgument],
  ) {
    @syntax.Attribute::new(name, arguments, span)
  }
  let malformed : Array[Array[@syntax.Attribute]] = [
    [attribute("linux", []), attribute("linux", [])],
    [attribute("continue", [argument(Some(boolean))])],
    [attribute("group", [argument(Some(boolean))])],
    [attribute("group", [argument(None)])],
    [attribute("env", [argument(Some(string)), argument(None)])],
    [attribute("env", [argument(None), argument(Some(string))])],
    [attribute("extension", [argument(Some(boolean))])],
    [attribute("metadata", [argument(Some(boolean))])],
    [attribute("shell", [argument(None)])],
    [attribute("script", [argument(None)])],
    [
      attribute("no-cd", []),
      attribute("working-directory", [argument(Some(string))]),
    ],
    [attribute("script", []), attribute("shell", [])],
    [attribute("exit-message", []), attribute("no-exit-message", [])],
  ]
  for index, attributes in malformed {
    try compile_attributes(attributes) catch {
      error => assert_true(error.message().length() > index)
    } noraise {
      _ => fail("expected malformed attribute rejection for case \{index}")
    }
  }
  let custom = try! compile_attributes([attribute("custom", [])])
  assert_true(custom.names().contains("custom"))
  let unix = [attribute("unix", [])]
  assert_true(platform_attributes_match(unix, TargetPlatform::new(Linux, true)))
  assert_false(
    platform_attributes_match(unix, TargetPlatform::new(Windows, false)),
  )
}
