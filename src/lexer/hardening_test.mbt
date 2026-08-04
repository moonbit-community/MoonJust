///|
fn hardened_source(text : String) -> @source.Source {
  @source.Source::from_text(@source.SourceId::new(24), "fuzz.just", text)
}

///|
fn next_random(seed : Int) -> Int {
  (seed * 25173 + 13849) % 65521
}

///|
fn generated_input(seed : Int) -> (String, Int) {
  let alphabet = [
    "a", "Z", "_", "0", "-", " ", "\t", "\n", "\r", "#", ":", "=", "+", "!", "~",
    "&", "|", "(", ")", "[", "]", "{", "}", "'", "\"", "`", "\\", "@", "$", "?",
    "/", "*", ",", "中", "🙂",
  ]
  let mut state = next_random(seed)
  let length = state % 17
  let builder = StringBuilder()
  for _index = 0; _index < length; _index = _index + 1 {
    state = next_random(state)
    builder.write_string(alphabet[state % alphabet.length()])
  }
  (builder.to_string(), state)
}

///|
fn assert_success_invariants(
  stream : @lexer.TokenStream,
  input : @source.Source,
) -> Unit raise {
  let tokens = stream.tokens()
  assert_true(!tokens.is_empty())
  assert_eq(tokens[tokens.length() - 1].kind(), Eof)
  let roundtrip = StringBuilder()
  let mut previous_end = 0
  for token in tokens {
    let span = token.span()
    assert_eq(span.source_id(), input.id())
    assert_true(span.start_byte() >= previous_end)
    assert_true(span.end_byte() >= span.start_byte())
    assert_true(span.end_byte() <= input.length())
    if token.is_synthetic() {
      assert_true(span.is_empty())
    }
    roundtrip.write_string(token.lexeme(input))
    previous_end = span.end_byte()
  }
  assert_eq(roundtrip.to_string(), input.text())
}

///|
test "100000 deterministic UTF-8 inputs never panic or escape typed failures" {
  let mut seed = 1
  for case = 0; case < 100000; case = case + 1 {
    let (text, next) = generated_input(seed)
    seed = next + case % 17
    let input = hardened_source(text)
    try @lexer.lex(input) catch {
      _ => ()
    } noraise {
      stream => assert_success_invariants(stream, input)
    }
  }
}

///|
test "source, token, and nesting budgets fail with typed spans" {
  let input = hardened_source("a b c")
  let source_limits = @lexer.LexerLimits::new(4, 100, 10)
  try @lexer.lex_with_limits(input, source_limits) catch {
    SourceLimitExceeded(length=5, limit=4, span~) =>
      assert_eq(span, input.full_span())
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected source limit")
  }
  let token_limits = @lexer.LexerLimits::new(100, 2, 10)
  try @lexer.lex_with_limits(input, token_limits) catch {
    TokenLimitExceeded(limit=2, span~) => assert_true(span.start_byte() >= 2)
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected token limit")
  }
  let zero_token_limits = @lexer.LexerLimits::new(100, 0, 10)
  let recipe = hardened_source("a:\n {{x}}")
  try @lexer.lex_with_limits(recipe, zero_token_limits) catch {
    TokenLimitExceeded(limit=0, span~) => assert_eq(span.start_byte(), 0)
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected zero-token limit")
  }
  let nested = hardened_source("((value))")
  let nesting_limits = @lexer.LexerLimits::new(100, 100, 1)
  try @lexer.lex_with_limits(nested, nesting_limits) catch {
    NestingLimitExceeded(limit=1, span~) => {
      assert_eq(span.start_byte(), 1)
      assert_eq(span.length(), 1)
    }
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected nesting limit")
  }
}

///|
test "line-continuation errors match upstream in-progress token spans" {
  let invalid = hardened_source("\\x")
  try @lexer.lex(invalid) catch {
    InvalidEscapeSequence(character="x", span~) => {
      assert_eq(span.start_byte(), 0)
      assert_eq(span.length(), 1)
    }
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected invalid line continuation")
  }
  let carriage = hardened_source("\\\rX")
  try @lexer.lex(carriage) catch {
    UnpairedCarriageReturn(span~) => {
      assert_eq(span.start_byte(), 0)
      assert_eq(span.length(), 2)
    }
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected unpaired continuation carriage return")
  }
}

///|
test "invalid budgets and diagnostic conversion remain stable" {
  try @lexer.LexerLimits::new(-1, 1, 1) catch {
    InvalidLexerLimit(name="max_source_bytes", value=-1) => ()
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected invalid configuration")
  }
  let input = hardened_source("%")
  try @lexer.lex(input) catch {
    UnknownStartOfToken(start~, span~) => {
      let error : @lexer.LexerError = UnknownStartOfToken(start~, span~)
      let diagnostic = error.to_diagnostic()
      assert_eq(diagnostic.code(), "MJ-LEX-0001")
      assert_eq(diagnostic.message(), "unknown start of token '%'")
      assert_eq(
        diagnostic.primary().span(),
        @source.Span::new(input.id(), 0, 1),
      )
    }
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected lexical diagnostic")
  }
}
