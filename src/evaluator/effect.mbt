///|
fn expect_string(
  name : String,
  arguments : Array[Value],
  index : Int,
  span : @source.Span,
) -> String raise EvaluationError {
  if index >= arguments.length() {
    raise TypeMismatch(expected=name + " argument", actual="missing", span~)
  }
  match arguments[index] {
    String(value) => value
    value => raise TypeMismatch(expected="string", actual=value.kind(), span~)
  }
}

///|
fn bytes_text(
  bytes : Bytes,
  span : @source.Span,
) -> String raise EvaluationError {
  @utf8.decode(bytes) catch {
    _ => raise InvalidUtf8(span~)
  }
}

///|
fn hex_byte(byte : Byte, builder : StringBuilder) -> Unit {
  let digits = [
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
  ]
  builder.write_char(digits[(byte.to_int() >> 4) & 15])
  builder.write_char(digits[byte.to_int() & 15])
}

///|
fn uuid_text(bytes : Bytes) -> String {
  let builder = StringBuilder()
  for index, byte in bytes {
    if index == 4 || index == 6 || index == 8 || index == 10 {
      builder.write_char('-')
    }
    let value = if index == 6 {
      ((byte.to_int() & 15) | 64).to_byte()
    } else if index == 8 {
      ((byte.to_int() & 63) | 128).to_byte()
    } else {
      byte
    }
    hex_byte(value, builder)
  }
  builder.to_string()
}

///|
/// Invoke a builtin that requires explicitly supplied host capabilities.
pub fn[
  T : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostProcess,
] call_effect(
  host : T,
  name : String,
  arguments : Array[Value],
  cwd : @path.PathValue,
  span : @source.Span,
) -> Value raise EvaluationError {
  match name {
    "env" => {
      let key = expect_string(name, arguments, 0, span)
      let value = @host.HostEnv::env_get(host, key) catch {
        error => raise Host(error, span~)
      }
      String(value.unwrap_or(""))
    }
    "read" => {
      let raw = expect_string(name, arguments, 0, span)
      let path = @path.PathValue::new(raw, cwd.flavor()) catch {
        _ => raise TypeMismatch(expected="path", actual=raw, span~)
      }
      let bytes = @host.HostFs::read_file(host, path) catch {
        error => raise Host(error, span~)
      }
      String(bytes_text(bytes, span))
    }
    "sha256_file" => {
      let raw = expect_string(name, arguments, 0, span)
      let path = @path.PathValue::new(raw, cwd.flavor()) catch {
        _ => raise TypeMismatch(expected="path", actual=raw, span~)
      }
      let bytes = @host.HostFs::read_file(host, path) catch {
        error => raise Host(error, span~)
      }
      String(@builtin.sha256_bytes(bytes))
    }
    "blake3_file" => {
      let raw = expect_string(name, arguments, 0, span)
      let path = @path.PathValue::new(raw, cwd.flavor()) catch {
        _ => raise TypeMismatch(expected="path", actual=raw, span~)
      }
      let bytes = @host.HostFs::read_file(host, path) catch {
        error => raise Host(error, span~)
      }
      String(@builtin.blake3_bytes(bytes))
    }
    "path_exists" => {
      let raw = expect_string(name, arguments, 0, span)
      let path = @path.PathValue::new(raw, cwd.flavor()) catch {
        _ => raise TypeMismatch(expected="path", actual=raw, span~)
      }
      Bool(
        @host.HostFs::file_exists(host, path) catch {
          error => raise Host(error, span~)
        },
      )
    }
    "write" => {
      let raw = expect_string(name, arguments, 0, span)
      let contents = expect_string(name, arguments, 1, span)
      let path = @path.PathValue::new(raw, cwd.flavor()) catch {
        _ => raise TypeMismatch(expected="path", actual=raw, span~)
      }
      @host.HostFs::write_file(host, path, @utf8.encode(contents)) catch {
        error => raise Host(error, span~)
      }
      String("")
    }
    "now_millis" => {
      let value = @host.HostClock::now_millis(host) catch {
        error => raise Host(error, span~)
      }
      String(value.to_string())
    }
    "uuid" => {
      let bytes = @host.HostRandom::random_bytes(host, 16) catch {
        error => raise Host(error, span~)
      }
      String(uuid_text(bytes))
    }
    "shell" => {
      let command = expect_string(name, arguments, 0, span)
      let spec = @host.CommandSpec::new("sh", ["-c", command]) catch {
        error => raise Host(error, span~)
      }
      spec.set_cwd(cwd)
      let output = @host.HostProcess::run_process(host, spec) catch {
        error => raise Host(error, span~)
      }
      if output.exit_code() != 0 {
        raise ProcessFailure(code=output.exit_code(), span~)
      }
      let text = bytes_text(output.stdout().to_owned(), span)
      String(text.trim_end().to_owned())
    }
    _ =>
      @builtin.call(name, arguments) catch {
        error => raise Builtin(error, span~)
      }
  }
}

///|
pub fn[
  T : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostProcess,
] evaluate_backtick(
  host : T,
  command : String,
  cwd : @path.PathValue,
  span : @source.Span,
) -> Value raise EvaluationError {
  call_effect(host, "shell", [String(command)], cwd, span)
}
