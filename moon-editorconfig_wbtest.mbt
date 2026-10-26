///|
test "facade parses ordered text" {
  let document = parse("root=true\n[*.mbt]\nindent_size=2", source="demo")
  assert_eq(document.source, "demo")
  assert_eq(document.sections.length(), 1)
  assert_eq(document.sections[0].properties[0].key, "indent_size")
}

///|
test "facade compiles and matches glob" {
  guard compile_glob("*.{mbt,md}").glob is Some(compiled) else {
    fail("expected compiled glob")
  }
  assert_true(glob_matches(compiled, "src/main.mbt"))
  assert_false(glob_matches(compiled, "src/main.txt"))
}

///|
test "facade resolves and explains in-memory files" {
  let source = memory_source([
    config_file("/repo/.editorconfig", "root=true\n[*.mbt]\nindent_size=2"),
  ])
  let result = resolve("/repo/src/main.mbt", source)
  assert_eq(result.value("indent_size"), Some("2"))
  let detailed = explain("/repo/src/main.mbt", source)
  assert_true(detailed.settings.trace.length() >= 2)
}

///|
test "facade diagnostic match distinguishes budget exhaustion from a miss" {
  let limits = { ..@model.default_limits(), max_match_operations: 8, }
  guard compile_glob("**needle", limits~).glob is Some(compiled) else {
    fail("expected compiled glob")
  }
  let result = match_glob(compiled, "a/b/c/d/e/needle")
  assert_true(result.exhausted)
  assert_eq(result.operations, 8)
  assert_eq(result.diagnostics[0].code, "E_GLOB_MATCH_LIMIT")
  guard compile_glob("*.mbt").glob is Some(ordinary) else {
    fail("expected compiled glob")
  }
  let miss = match_glob(ordinary, "main.txt")
  assert_false(miss.matched)
  assert_false(miss.exhausted)
  assert_true(miss.diagnostics.is_empty())
}

///|
test "facade JSON is stable and parseable" {
  let document = parse("[*]\ncustom_key=value")
  let first = document_json(document)
  assert_eq(first, document_json(document))
  assert_true(first.contains("\"custom_key\""))
}
