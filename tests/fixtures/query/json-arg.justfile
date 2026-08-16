set lists
set unstable
set shell := ["sh", "-cu"]
set dotenv-command := "echo FOO=bar"

base:

[arg("items", short="i", multiple, pattern=["one", "two"], min="1", max="2")]
[arg("bar", long, flag, help="hello")]
[continue("SIGINT", "SIGHUP")]
[metadata("query", "json")]
foo bar items: base && cleanup
  #!/bin/sh
  echo foo

cleanup:
