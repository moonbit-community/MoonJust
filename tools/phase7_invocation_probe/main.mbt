///|
extern "c" fn exit(code : Int) = "exit"

///|
async fn fail(message : String) -> Unit {
  @stdio.stderr.write(@utf8.encode("error: " + message + "\n")) catch {
    _ => ()
  }
  exit(1)
}

///|
fn render(
  compilation : @semantic.Compilation,
  invocation : @invocation.Invocation,
) -> String {
  let builder = StringBuilder()
  builder.write_string("echo")
  guard compilation.recipe(invocation.recipe()) is Some(recipe) else {
    return ""
  }
  for index, parameter in recipe.parameters() {
    builder.write_char(' ')
    builder.write_string(parameter.name())
    builder.write_char('=')
    builder.write_string(invocation.arguments()[index].elements().join(" "))
  }
  builder.write_char('\n')
  builder.to_string()
}

///|
async fn main {
  let source_text = @stdio.stdin.read_all().text() catch {
      _ => {
        fail("failed to read justfile fixture")
        return
      }
    }
  let source = @source.Source::from_text(
    @source.SourceId::new(1),
    "justfile",
    source_text,
  )
  let compilation = try
    @semantic.compile_source(source, allow_unstable=true)
  catch {
    error => {
      fail(error.message())
      return
    }
  } noraise {
    value => value
  }
  let argv = @env.args()[1:]
  let invocations = try @invocation.parse_invocations(compilation, argv) catch {
    error => {
      fail(error.message())
      return
    }
  } noraise {
    value => value
  }
  let output = StringBuilder()
  for invocation in invocations {
    output.write_string(render(compilation, invocation))
  }
  @stdio.stdout.write(@utf8.encode(output.to_string()))
}
