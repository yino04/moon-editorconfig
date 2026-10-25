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
test "facade JSON is stable and parseable" {
  let document = parse("[*]\ncustom_key=value")
  let first = document_json(document)
  assert_eq(first, document_json(document))
  assert_true(first.contains("\"custom_key\""))
}
