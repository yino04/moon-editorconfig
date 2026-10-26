///|
test "public consumer resolves nested override and unset" {
  let source = @moon-editorconfig.memory_source([
    @moon-editorconfig.config_file(
      "/repo/.editorconfig", "root=true\n[*.mbt]\nindent_size=2\nend_of_line=lf",
    ),
    @moon-editorconfig.config_file(
      "/repo/src/.editorconfig", "[*.mbt]\nindent_size=4\nend_of_line=unset",
    ),
  ])
  let result = @moon-editorconfig.explain("/repo/src/main.mbt", source)
  assert_false(result.has_errors())
  assert_eq(result.value("indent_size"), Some("4"))
  assert_eq(result.value("end_of_line"), None)
  guard result.get("indent_size") is Some(property) else {
    fail("expected effective indent_size")
  }
  assert_eq(property.config_path, "/repo/src/.editorconfig")
  assert_true(result.settings.trace.length() >= 4)
}
