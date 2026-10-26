///|
fn main {
  let source = @editorconfig.memory_source([
    @editorconfig.config_file(
      "/repo/.editorconfig", "root=true\n[*.mbt]\nindent_size=2\nend_of_line=lf",
    ),
    @editorconfig.config_file(
      "/repo/src/.editorconfig", "[*.mbt]\nindent_size=4\nend_of_line=unset",
    ),
  ])
  let result = @editorconfig.explain("/repo/src/main.mbt", source)
  println(@editorconfig.settings_json(result.settings))
}
