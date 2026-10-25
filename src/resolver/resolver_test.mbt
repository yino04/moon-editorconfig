///|
fn one_file(path : String, text : String) -> @resolver.MemoryConfigSource {
  @resolver.memory_source([@resolver.config_file(path, text)])
}

///|
fn has_diagnostic(result : @resolver.ResolveResult, code : String) -> Bool {
  result.settings.diagnostics.any(fn(diagnostic) { diagnostic.code == code })
}

///|
test "config files normalize their lexical paths" {
  let file = @resolver.config_file("C:\\repo\\.editorconfig", "root=true")
  assert_eq(file.path, "C:/repo/.editorconfig")
  assert_eq(file.text, "root=true")
}

///|
test "memory source uses deterministic last-entry-wins overlays" {
  let source = @resolver.empty_memory_source()
  source.put("/repo/.editorconfig", "[*]\nindent_size=2")
  source.put("/repo/./.editorconfig", "[*]\nindent_size=4")
  assert_eq(source.file_count(), 2)
  guard source.lookup("/repo/.editorconfig", @path.CaseSensitive) is Some(file) else {
    fail("expected overlay file")
  }
  assert_true(file.text.contains("=4"))
}

///|
test "empty source returns empty settings and complete search order" {
  let result = @resolver.resolve(
    "/repo/src/main.mbt",
    @resolver.empty_memory_source(),
    @path.CaseSensitive,
  )
  assert_eq(result.settings.properties.length(), 0)
  assert_eq(result.searched_config_paths, [
    "/repo/src/.editorconfig", "/repo/.editorconfig", "/.editorconfig",
  ])
  assert_eq(result.loaded_config_paths, [])
}

///|
test "single matching config assigns a standard property" {
  let result = @resolver.resolve(
    "/repo/main.mbt",
    one_file("/repo/.editorconfig", "[*.mbt]\nindent_size = 2"),
    @path.CaseSensitive,
  )
  assert_eq(result.value("indent_size"), Some("2"))
  assert_eq(result.settings.trace.length(), 1)
  assert_eq(result.settings.trace[0].action, @model.Assign)
}

///|
test "root true stops discovery but still applies its own sections" {
  let source = @resolver.memory_source([
    @resolver.config_file("/.editorconfig", "[*]\nindent_size=8"),
    @resolver.config_file(
      "/repo/.editorconfig", "root=true\n[*]\nindent_size=2",
    ),
  ])
  let result = @resolver.resolve(
    "/repo/src/main.mbt",
    source,
    @path.CaseSensitive,
  )
  assert_eq(result.value("indent_size"), Some("2"))
  assert_eq(result.loaded_config_paths, ["/repo/.editorconfig"])
  assert_eq(result.stopped_by_root, Some("/repo/.editorconfig"))
  assert_eq(result.searched_config_paths, [
    "/repo/src/.editorconfig", "/repo/.editorconfig",
  ])
}

///|
test "root false continues discovery to the lexical root" {
  let source = @resolver.memory_source([
    @resolver.config_file("/.editorconfig", "[*]\nindent_size=8"),
    @resolver.config_file(
      "/repo/.editorconfig", "root=false\n[*]\nindent_size=4",
    ),
  ])
  let result = @resolver.resolve("/repo/main.mbt", source, @path.CaseSensitive)
  assert_eq(result.loaded_config_paths, [
    "/.editorconfig", "/repo/.editorconfig",
  ])
  assert_eq(result.value("indent_size"), Some("4"))
  assert_eq(result.stopped_by_root, None)
}

///|
test "ancestor files apply before closer descendant files" {
  let source = @resolver.memory_source([
    @resolver.config_file("/.editorconfig", "[*]\nindent_size=8"),
    @resolver.config_file("/repo/.editorconfig", "[*]\nindent_size=4"),
    @resolver.config_file("/repo/src/.editorconfig", "[*]\nindent_size=2"),
  ])
  let result = @resolver.resolve(
    "/repo/src/main.mbt",
    source,
    @path.CaseSensitive,
  )
  assert_eq(result.loaded_config_paths, [
    "/.editorconfig", "/repo/.editorconfig", "/repo/src/.editorconfig",
  ])
  assert_eq(result.value("indent_size"), Some("2"))
  assert_eq(result.settings.trace.map(fn(event) { event.action }), [
    @model.Assign,
    @model.Override,
    @model.Override,
  ])
}

///|
test "later matching sections in one file override earlier sections" {
  let result = @resolver.resolve(
    "/repo/main.mbt",
    one_file(
      "/repo/.editorconfig", "[*]\nindent_size=2\n[*.mbt]\nindent_size=4",
    ),
    @path.CaseSensitive,
  )
  assert_eq(result.value("indent_size"), Some("4"))
  assert_eq(result.settings.trace[1].action, @model.Override)
  assert_eq(result.settings.trace[1].section_glob, "*.mbt")
}

///|
test "later duplicate properties override in source order" {
  let result = @resolver.resolve(
    "/repo/main.mbt",
    one_file("/repo/.editorconfig", "[*.mbt]\nindent_size=2\nindent_size=6"),
    @path.CaseSensitive,
  )
  assert_eq(result.value("indent_size"), Some("6"))
  assert_true(has_diagnostic(result, "W_DUPLICATE_PROPERTY"))
  assert_eq(result.settings.trace[0].value, "2")
  assert_eq(result.settings.trace[1].value, "6")
}

///|
test "resolve omits ordinary nonmatches from its compact trace" {
  let result = @resolver.resolve(
    "/repo/main.mbt",
    one_file("/repo/.editorconfig", "[*.rs]\nindent_size=2"),
    @path.CaseSensitive,
  )
  assert_eq(result.value("indent_size"), None)
  assert_eq(result.settings.trace, [])
}

///|
test "explain records section no-match as an Ignore event" {
  let result = @resolver.explain(
    "/repo/main.mbt",
    one_file("/repo/.editorconfig", "[*.rs]\nindent_size=2"),
    @path.CaseSensitive,
  )
  assert_eq(result.settings.trace.length(), 1)
  assert_eq(result.settings.trace[0].action, @model.Ignore)
  assert_eq(result.settings.trace[0].section_glob, "*.rs")
  assert_true(result.settings.trace[0].note.contains("did not match"))
}

///|
test "pattern without slash matches a basename at arbitrary depth" {
  let result = @resolver.resolve(
    "/repo/src/deep/main.mbt",
    one_file("/repo/.editorconfig", "[*.mbt]\nindent_size=2"),
    @path.CaseSensitive,
  )
  assert_eq(result.value("indent_size"), Some("2"))
}

///|
test "pattern with slash is relative to the config directory" {
  let source = one_file("/repo/.editorconfig", "[src/*.mbt]\nindent_size=2")
  let direct = @resolver.resolve(
    "/repo/src/main.mbt",
    source,
    @path.CaseSensitive,
  )
  let nested = @resolver.resolve(
    "/repo/src/deep/main.mbt",
    source,
    @path.CaseSensitive,
  )
  assert_eq(direct.value("indent_size"), Some("2"))
  assert_eq(nested.value("indent_size"), None)
}

///|
test "leading slash glob remains anchored to the config directory" {
  let source = one_file("/repo/.editorconfig", "[/src/*.mbt]\nindent_size=2")
  assert_eq(
    @resolver.resolve("/repo/src/main.mbt", source, @path.CaseSensitive).value(
      "indent_size",
    ),
    Some("2"),
  )
}

///|
test "unset removes a value inherited from an ancestor" {
  let source = @resolver.memory_source([
    @resolver.config_file("/.editorconfig", "[*]\nindent_size=8"),
    @resolver.config_file("/repo/.editorconfig", "[*.mbt]\nindent_size=unset"),
  ])
  let result = @resolver.resolve("/repo/main.mbt", source, @path.CaseSensitive)
  assert_eq(result.value("indent_size"), None)
  assert_eq(result.settings.trace[1].action, @model.Unset)
  assert_true(result.settings.trace[1].note.contains("/.editorconfig"))
}

///|
test "unset without an active value is still visible in trace" {
  let result = @resolver.resolve(
    "/repo/main.mbt",
    one_file("/repo/.editorconfig", "[*]\nindent_size=unset"),
    @path.CaseSensitive,
  )
  assert_eq(result.value("indent_size"), None)
  assert_eq(result.settings.trace[0].action, @model.Unset)
  assert_eq(result.settings.trace[0].note, "no active value to remove")
}

///|
test "unknown custom properties and values are retained" {
  let result = @resolver.resolve(
    "/repo/main.mbt",
    one_file("/repo/.editorconfig", "[*]\ncustom_tool_option = Value # 1"),
    @path.CaseSensitive,
  )
  assert_eq(result.value("custom_tool_option"), Some("Value # 1"))
  assert_eq(result.settings.diagnostics.length(), 0)
}

///|
test "known values are normalized before becoming effective" {
  let result = @resolver.resolve(
    "/repo/main.mbt",
    one_file(
      "/repo/.editorconfig", "[*]\nindent_style=SPACE\ncharset=UTF-8\nspelling_language=zh-cn",
    ),
    @path.CaseSensitive,
  )
  assert_eq(result.value("indent_style"), Some("space"))
  assert_eq(result.value("charset"), Some("utf-8"))
  assert_eq(result.value("spelling_language"), Some("zh-CN"))
}

///|
test "invalid known values are diagnosed and ignored" {
  let result = @resolver.explain(
    "/repo/main.mbt",
    one_file("/repo/.editorconfig", "[*]\nindent_size=0"),
    @path.CaseSensitive,
  )
  assert_eq(result.value("indent_size"), None)
  assert_true(has_diagnostic(result, "E_PROP_VALUE"))
  assert_eq(result.settings.trace[0].action, @model.Ignore)
  assert_true(result.settings.trace[0].note.contains("invalid"))
}

///|
test "parser diagnostics aggregate while later recoverable sections apply" {
  let result = @resolver.resolve(
    "/repo/main.mbt",
    one_file("/repo/.editorconfig", "this is invalid\n[*.mbt]\nindent_size=2"),
    @path.CaseSensitive,
  )
  assert_true(has_diagnostic(result, "EC2001"))
  assert_eq(result.value("indent_size"), Some("2"))
}

///|
test "diagnostics aggregate in ancestor-to-descendant application order" {
  let source = @resolver.memory_source([
    @resolver.config_file("/.editorconfig", "bad root line\n[*]\nindent_size=2"),
    @resolver.config_file(
      "/repo/.editorconfig", "another bad line\n[*]\nindent_size=4",
    ),
  ])
  let result = @resolver.resolve("/repo/main.mbt", source, @path.CaseSensitive)
  assert_eq(
    result.settings.diagnostics[0].span.unwrap().source,
    "/.editorconfig",
  )
  assert_eq(
    result.settings.diagnostics[1].span.unwrap().source,
    "/repo/.editorconfig",
  )
}

///|
test "custom config filename participates in upward discovery" {
  let source = one_file("/repo/settings.ec", "[*]\nindent_size=3")
  let options = @resolver.resolve_options(
    @path.CaseSensitive,
    config_name="settings.ec",
  )
  let result = @resolver.resolve_with_options(
    "/repo/src/main.mbt", source, options,
  )
  assert_eq(result.value("indent_size"), Some("3"))
  assert_true(result.searched_config_paths.contains("/repo/settings.ec"))
}

///|
test "ASCII-insensitive lookup handles Windows drive and directory casing" {
  let source = one_file(
    "c:\\Repo\\.editorconfig", "root=true\n[*.mbt]\nindent_size=2",
  )
  let result = @resolver.resolve(
    "C:\\REPO\\src\\main.mbt",
    source,
    @path.AsciiCaseInsensitive,
  )
  assert_eq(result.value("indent_size"), Some("2"))
  assert_eq(result.stopped_by_root, Some("c:/Repo/.editorconfig"))
  assert_eq(result.settings.target_path, "C:/REPO/src/main.mbt")
}

///|
test "case-sensitive lookup does not silently emulate Windows" {
  let source = one_file("C:/Repo/.editorconfig", "[*.mbt]\nindent_size=2")
  let result = @resolver.resolve(
    "C:/repo/main.mbt",
    source,
    @path.CaseSensitive,
  )
  assert_eq(result.value("indent_size"), None)
  assert_eq(result.loaded_config_paths, [])
}

///|
test "path case policy does not change specification glob casing" {
  let source = one_file("C:/Repo/.editorconfig", "[*.MBT]\nindent_size=2")
  let result = @resolver.explain(
    "c:/repo/main.mbt",
    source,
    @path.AsciiCaseInsensitive,
  )
  assert_eq(result.value("indent_size"), None)
  assert_true(result.settings.trace[0].note.contains("did not match"))
}

///|
test "drive-root discovery applies root then descendant configs" {
  let source = @resolver.memory_source([
    @resolver.config_file("C:/.editorconfig", "[*]\nindent_size=8"),
    @resolver.config_file("C:/repo/.editorconfig", "[*]\nindent_size=2"),
  ])
  let result = @resolver.resolve(
    "C:/repo/src/main.mbt",
    source,
    @path.CaseSensitive,
  )
  assert_eq(result.loaded_config_paths, [
    "C:/.editorconfig", "C:/repo/.editorconfig",
  ])
  assert_eq(result.value("indent_size"), Some("2"))
}

///|
test "UNC discovery stops at share root and honors root true" {
  let source = one_file(
    "//Server/Share/.editorconfig", "root=true\n[*.mbt]\nindent_size=2",
  )
  let result = @resolver.resolve(
    "\\\\server\\share\\dir\\main.mbt",
    source,
    @path.AsciiCaseInsensitive,
  )
  assert_eq(result.value("indent_size"), Some("2"))
  assert_eq(result.loaded_config_paths, ["//Server/Share/.editorconfig"])
  assert_eq(result.searched_config_paths, [
    "//server/share/dir/.editorconfig", "//server/share/.editorconfig",
  ])
}

///|
test "root preamble controls discovery but never becomes a setting" {
  let result = @resolver.explain(
    "/repo/main.mbt",
    one_file("/repo/.editorconfig", "root=true\n[*]\nindent_size=2"),
    @path.CaseSensitive,
  )
  assert_eq(result.value("root"), None)
  assert_eq(result.settings.trace[0].action, @model.Ignore)
  assert_eq(result.settings.trace[0].key, "root")
  assert_eq(result.settings.trace[1].action, @model.Assign)
}

///|
test "non-root preamble pairs produce diagnostics and explain trace" {
  let result = @resolver.explain(
    "/repo/main.mbt",
    one_file("/repo/.editorconfig", "indent_size=8\n[*]\ncharset=utf-8"),
    @path.CaseSensitive,
  )
  assert_eq(result.value("indent_size"), None)
  assert_eq(result.value("charset"), Some("utf-8"))
  assert_true(has_diagnostic(result, "W_PREAMBLE_IGNORED"))
  assert_eq(result.settings.trace[0].action, @model.Ignore)
}

///|
test "root property inside a section is ignored" {
  let result = @resolver.explain(
    "/repo/main.mbt",
    one_file("/repo/.editorconfig", "[*]\nroot=true\nindent_size=2"),
    @path.CaseSensitive,
  )
  assert_eq(result.value("root"), None)
  assert_eq(result.value("indent_size"), Some("2"))
  assert_true(has_diagnostic(result, "E_ROOT_LOCATION"))
  assert_eq(result.settings.trace[0].action, @model.Ignore)
}

///|
test "strict parser options stop before later valid sections" {
  let source = one_file(
    "/repo/.editorconfig", "invalid line\n[*.mbt]\nindent_size=2",
  )
  let options = @resolver.resolve_options(
    @path.CaseSensitive,
    parse_options=@model.strict_parse_options(),
  )
  let result = @resolver.resolve_with_options("/repo/main.mbt", source, options)
  assert_true(has_diagnostic(result, "EC2001"))
  assert_eq(result.value("indent_size"), None)
}

///|
test "relative target paths discover a relative root config" {
  let result = @resolver.resolve(
    "src/main.mbt",
    one_file(".editorconfig", "[src/*.mbt]\nindent_size=2"),
    @path.CaseSensitive,
  )
  assert_eq(result.value("indent_size"), Some("2"))
  assert_eq(result.searched_config_paths, ["src/.editorconfig", ".editorconfig"])
}

///|
test "effective property order is stable across overrides" {
  let result = @resolver.resolve(
    "/repo/main.mbt",
    one_file("/repo/.editorconfig", "[*]\nalpha=1\nbeta=2\n[*.mbt]\nalpha=3"),
    @path.CaseSensitive,
  )
  assert_eq(result.settings.properties.map(fn(property) { property.key }), [
    "alpha", "beta",
  ])
  assert_eq(result.value("alpha"), Some("3"))
}

///|
test "reassignment after unset receives a new stable position" {
  let result = @resolver.resolve(
    "/repo/main.mbt",
    one_file(
      "/repo/.editorconfig", "[*]\nalpha=1\nbeta=2\nalpha=unset\nalpha=3",
    ),
    @path.CaseSensitive,
  )
  assert_eq(result.settings.properties.map(fn(property) { property.key }), [
    "beta", "alpha",
  ])
  assert_eq(result.value("alpha"), Some("3"))
}

///|
test "trace order is ancestor then descendant then section source order" {
  let source = @resolver.memory_source([
    @resolver.config_file("/.editorconfig", "[*]\nalpha=root"),
    @resolver.config_file(
      "/repo/.editorconfig", "[*]\nalpha=repo\n[*.mbt]\nbeta=file",
    ),
  ])
  let result = @resolver.resolve("/repo/main.mbt", source, @path.CaseSensitive)
  assert_eq(result.settings.trace.map(fn(event) { event.value }), [
    "root", "repo", "file",
  ])
  assert_eq(result.settings.trace.map(fn(event) { event.config_path }), [
    "/.editorconfig", "/repo/.editorconfig", "/repo/.editorconfig",
  ])
}

///|
test "explain is deterministic for identical source and options" {
  let source = one_file(
    "/repo/.editorconfig", "root=false\n[*.rs]\nalpha=no\n[*.mbt]\nalpha=yes",
  )
  let first = @resolver.explain("/repo/main.mbt", source, @path.CaseSensitive)
  let second = @resolver.explain(
    "/repo/./main.mbt",
    source,
    @path.CaseSensitive,
  )
  assert_eq(first, second)
}
