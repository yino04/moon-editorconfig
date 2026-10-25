///|
test "no arguments requests help" {
  assert_eq(@cli.parse_arguments([]), Ok(@cli.Help))
}

///|
test "help aliases request help" {
  assert_eq(@cli.parse_arguments(["--help"]), Ok(@cli.Help))
  assert_eq(@cli.parse_arguments(["-h"]), Ok(@cli.Help))
  assert_eq(@cli.parse_arguments(["help"]), Ok(@cli.Help))
}

///|
test "version aliases request version" {
  assert_eq(@cli.parse_arguments(["--version"]), Ok(@cli.Version))
  assert_eq(@cli.parse_arguments(["-V"]), Ok(@cli.Version))
}

///|
test "parse recognizes JSON in either tail position" {
  assert_eq(
    @cli.parse_arguments(["parse", "demo.ec", "--json"]),
    Ok(@cli.Parse("demo.ec", true)),
  )
  assert_eq(
    @cli.parse_arguments(["parse", "--json", "demo.ec"]),
    Ok(@cli.Parse("demo.ec", true)),
  )
}

///|
test "match preserves pattern and relative path" {
  assert_eq(
    @cli.parse_arguments(["match", "*.{mbt,md}", "src/main.mbt"]),
    Ok(@cli.Match("*.{mbt,md}", "src/main.mbt", false)),
  )
}

///|
test "double dash permits a hyphen-leading pattern" {
  assert_eq(
    @cli.parse_arguments(["match", "--", "-draft*", "-draft.md"]),
    Ok(@cli.Match("-draft*", "-draft.md", false)),
  )
}

///|
test "validate records strict and JSON flags" {
  assert_eq(
    @cli.parse_arguments(["validate", "--strict", "--json", "config"]),
    Ok(@cli.Validate("config", true, true)),
  )
}

///|
test "strict is rejected outside validate" {
  guard @cli.parse_arguments(["parse", "--strict", "config"]) is Err(error) else {
    fail("expected usage error")
  }
  assert_true(error.message.contains("only valid with validate"))
}

///|
test "unknown options are rejected" {
  guard @cli.parse_arguments(["parse", "--yaml", "config"]) is Err(error) else {
    fail("expected usage error")
  }
  assert_true(error.message.contains("unknown option"))
}

///|
test "unknown commands are rejected" {
  guard @cli.parse_arguments(["format", "file.mbt"]) is Err(error) else {
    fail("expected usage error")
  }
  assert_true(error.message.contains("unknown command"))
}

///|
test "arity errors report expected and actual counts" {
  guard @cli.parse_arguments(["match", "*.mbt"]) is Err(error) else {
    fail("expected usage error")
  }
  assert_true(error.message.contains("expects 2"))
  assert_true(error.message.contains("got 1"))
}

///|
test "help response documents stable exit codes" {
  let response = @cli.help_response()
  assert_eq(response.exit_code, 0)
  assert_true(response.stdout.contains("moonecfg resolve"))
  assert_true(response.stdout.contains("5 resource budget"))
  assert_eq(response.stderr, "")
}

///|
test "usage response uses stderr and code two" {
  let response = @cli.usage_response({ message: "bad input", })
  assert_eq(response.exit_code, 2)
  assert_eq(response.stdout, "")
  assert_true(response.stderr.contains("error: bad input"))
}

///|
test "parse JSON is valid and deterministic" {
  let text = "root=true\n[*.mbt]\nindent_size=2\n"
  let first = @cli.parse_response(text, ".editorconfig", true)
  let second = @cli.parse_response(text, ".editorconfig", true)
  assert_eq(first, second)
  assert_eq(first.exit_code, 0)
  ignore(@json.parse(first.stdout))
}

///|
test "parse human response summarizes ordered document" {
  let response = @cli.parse_response("[a]\nx=1\ny=2", "memory", false)
  assert_true(response.stdout.contains("sections: 1"))
  assert_true(response.stdout.contains("properties: 2"))
  assert_eq(response.stderr, "")
}

///|
test "malformed config produces diagnostics and code three" {
  let response = @cli.parse_response("[broken\nx=y", "broken", false)
  assert_eq(response.exit_code, 3)
  assert_true(response.stderr.contains("EC2002"))
}

///|
test "validation catches invalid standard values" {
  let response = @cli.validate_response(
    "[*.mbt]\nindent_style=diagonal", "invalid", false, true,
  )
  assert_eq(response.exit_code, 3)
  assert_true(response.stdout.contains("\"valid\":false"))
  assert_true(response.stdout.contains("E_PROP_VALUE"))
  ignore(@json.parse(response.stdout))
}

///|
test "validation preserves unknown custom properties" {
  let response = @cli.validate_response(
    "[*]\ncompany_mode=careful", "custom", false, false,
  )
  assert_eq(response.exit_code, 0)
  assert_eq(response.stdout, "valid\n")
}

///|
test "match command reports true and false as success" {
  assert_eq(
    @cli.match_response("*.mbt", "src/main.mbt", false).stdout,
    "true\n",
  )
  let miss = @cli.match_response("src/*.mbt", "src/deep/main.mbt", false)
  assert_eq(miss.exit_code, 0)
  assert_eq(miss.stdout, "false\n")
}

///|
test "match JSON exposes bounded work" {
  let response = @cli.match_response("src/**/*.mbt", "src/deep/main.mbt", true)
  assert_eq(response.exit_code, 0)
  assert_true(response.stdout.contains("\"operations\":"))
  assert_true(response.stdout.contains("\"matched\":true"))
  ignore(@json.parse(response.stdout))
}

///|
test "oversized glob uses resource exit code" {
  let response = @cli.match_response("a".repeat(4097), "a", true)
  assert_eq(response.exit_code, 5)
  assert_true(response.stdout.contains("E_GLOB_LENGTH"))
}

///|
test "resolve response contains discovery metadata" {
  let source = @resolver.memory_source([
    @resolver.config_file(
      "/repo/.editorconfig", "root=true\n[*.mbt]\nindent_size=2",
    ),
  ])
  let result = @resolver.resolve(
    "/repo/src/main.mbt",
    source,
    @path.CaseSensitive,
  )
  let response = @cli.resolve_response(result, false, true)
  assert_eq(response.exit_code, 0)
  assert_true(response.stdout.contains("\"mode\":\"resolve\""))
  assert_true(response.stdout.contains("\"indent_size\""))
  assert_true(response.stdout.contains("\"stoppedByRoot\""))
  ignore(@json.parse(response.stdout))
}

///|
test "explain human response includes override trace" {
  let source = @resolver.memory_source([
    @resolver.config_file("/.editorconfig", "[*]\nindent_size=8"),
    @resolver.config_file("/repo/.editorconfig", "[*.mbt]\nindent_size=2"),
  ])
  let result = @resolver.explain("/repo/main.mbt", source, @path.CaseSensitive)
  let response = @cli.resolve_response(result, true, false)
  assert_true(response.stdout.contains("trace:"))
  assert_true(response.stdout.contains("override indent_size=2"))
}

///|
test "I/O errors are JSON escaped and use code four" {
  let response = @cli.io_error_response("a\"b", "denied\nnow", true)
  assert_eq(response.exit_code, 4)
  assert_eq(response.stderr, "")
  ignore(@json.parse(response.stdout))
}

///|
test "pre-document diagnostics stay valid JSON" {
  let diagnostic = @model.error_diagnostic("E_UTF8", "invalid input")
  let response = @cli.diagnostics_response([diagnostic], true)
  assert_eq(response.exit_code, 3)
  assert_eq(response.stderr, "")
  assert_true(response.stdout.contains("E_UTF8"))
  ignore(@json.parse(response.stdout))
}
