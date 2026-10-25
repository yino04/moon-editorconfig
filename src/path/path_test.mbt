///|
test "slash and backslash inputs normalize to slash" {
  assert_eq(@path.normalize("src\\nested/main.mbt"), "src/nested/main.mbt")
  assert_eq(@path.normalize("a//b\\\\c"), "a/b/c")
}

///|
test "empty and current relative paths normalize to dot" {
  assert_eq(@path.normalize(""), ".")
  assert_eq(@path.normalize("."), ".")
  assert_eq(@path.normalize("././"), ".")
}

///|
test "relative dot dot folds ordinary components" {
  assert_eq(@path.normalize("a/b/../c/./d"), "a/c/d")
  assert_eq(@path.normalize("a/.."), ".")
}

///|
test "relative dot dot is retained when no component can be folded" {
  assert_eq(@path.normalize("../../a/../b"), "../../b")
  assert_eq(@path.normalize("a/../../../b"), "../../b")
}

///|
test "rooted dot dot never crosses the root" {
  assert_eq(@path.normalize("/../../a/../b"), "/b")
  assert_eq(@path.normalize("\\..\\..\\x"), "/x")
}

///|
test "drive absolute paths retain their drive and root" {
  assert_eq(
    @path.normalize("C:\\work\\.\\src\\..\\main.mbt"),
    "C:/work/main.mbt",
  )
  assert_eq(@path.normalize("d:/../../x"), "d:/x")
  assert_true(@path.is_absolute("C:\\x"))
}

///|
test "drive relative paths stay distinct from drive absolute paths" {
  assert_eq(@path.normalize("C:src\\main.mbt"), "C:src/main.mbt")
  assert_eq(@path.normalize("C:foo/../bar"), "C:bar")
  assert_true(@path.is_relative("C:src"))
  assert_false(@path.path_equal("C:src", "C:/src", @path.AsciiCaseInsensitive))
}

///|
test "drive metadata is exposed without host inspection" {
  assert_eq(@path.drive("c:/src"), Some("c:"))
  assert_eq(@path.drive("D:src"), Some("D:"))
  assert_eq(@path.drive("/src"), None)
}

///|
test "UNC roots normalize separators and cannot be escaped" {
  assert_eq(
    @path.normalize("\\\\Server\\Share\\a\\..\\..\\x"),
    "//Server/Share/x",
  )
  assert_true(@path.is_unc("//server/share/dir"))
  assert_true(@path.is_absolute("//server/share/dir"))
}

///|
test "UNC server and share metadata are retained" {
  let value = "\\\\BuildHost\\Artifacts\\nightly\\app.zip"
  assert_eq(@path.unc_server(value), Some("BuildHost"))
  assert_eq(@path.unc_share(value), Some("Artifacts"))
  assert_eq(@path.drive(value), None)
}

///|
test "incomplete UNC input remains an ordinary rooted path" {
  assert_eq(@path.normalize("//server"), "/server")
  assert_false(@path.is_unc("//server"))
}

///|
test "absolute and relative classification covers every anchor" {
  assert_true(@path.is_absolute("/a"))
  assert_true(@path.is_absolute("C:/a"))
  assert_true(@path.is_absolute("//host/share/a"))
  assert_true(@path.is_relative("a"))
  assert_true(@path.is_relative("C:a"))
}

///|
test "dirname observes lexical roots" {
  assert_eq(@path.dirname("/a/b.txt"), "/a")
  assert_eq(@path.dirname("/a"), "/")
  assert_eq(@path.dirname("/"), "/")
  assert_eq(@path.dirname("a"), ".")
}

///|
test "dirname handles drives and UNC roots" {
  assert_eq(@path.dirname("C:/a/b"), "C:/a")
  assert_eq(@path.dirname("C:/"), "C:/")
  assert_eq(@path.dirname("C:a"), "C:")
  assert_eq(@path.dirname("//host/share/a"), "//host/share")
  assert_eq(@path.dirname("//host/share"), "//host/share")
}

///|
test "basename returns the final normalized component" {
  assert_eq(@path.basename("a/b/../c.txt"), "c.txt")
  assert_eq(@path.basename("/a/"), "a")
  assert_eq(@path.basename("."), ".")
  assert_eq(@path.basename("/"), "")
  assert_eq(@path.basename("C:/"), "")
}

///|
test "join folds a relative child against its base" {
  assert_eq(@path.join("/repo/src", "../README.md"), "/repo/README.md")
  assert_eq(@path.join("a/b", "../../c"), "c")
  assert_eq(@path.join("C:work", "src/main.mbt"), "C:work/src/main.mbt")
}

///|
test "join replaces its base for anchored or drive-prefixed children" {
  assert_eq(@path.join("/repo", "/tmp/file"), "/tmp/file")
  assert_eq(@path.join("C:/repo", "D:/tmp"), "D:/tmp")
  assert_eq(@path.join("/repo", "D:local"), "D:local")
  assert_eq(@path.join("/repo", "//host/share/x"), "//host/share/x")
}

///|
test "join many has a dot identity and handles replacement" {
  assert_eq(@path.join_many([]), ".")
  assert_eq(@path.join_many(["a", "b", "..", "c"]), "a/c")
  assert_eq(@path.join_many(["a", "/root", "x"]), "/root/x")
}

///|
test "ancestors are nearest first and include the POSIX root" {
  assert_eq(@path.ancestors("/repo/src/lib"), [
    "/repo/src/lib", "/repo/src", "/repo", "/",
  ])
}

///|
test "relative ancestors include current directory once" {
  assert_eq(@path.ancestors("src/lib"), ["src/lib", "src", "."])
  assert_eq(@path.ancestors("."), ["."])
}

///|
test "UNC ancestors stop at the share root" {
  assert_eq(@path.ancestors("//host/share/a/b"), [
    "//host/share/a/b", "//host/share/a", "//host/share",
  ])
}

///|
test "config search directories start at the target parent" {
  assert_eq(@path.config_search_directories("/repo/src/main.mbt"), [
    "/repo/src", "/repo", "/",
  ])
  assert_eq(@path.config_search_directories("src/main.mbt"), ["src", "."])
}

///|
test "config candidates are lexical and ordered nearest first" {
  assert_eq(@path.config_candidates("/repo/src/main.mbt"), [
    "/repo/src/.editorconfig", "/repo/.editorconfig", "/.editorconfig",
  ])
  assert_eq(
    @path.config_candidates("C:/repo/main.mbt", config_name="settings.ini"),
    ["C:/repo/settings.ini", "C:/settings.ini"],
  )
}

///|
test "case-sensitive comparison preserves spelling distinctions" {
  assert_false(
    @path.path_equal("/Repo/File", "/repo/file", @path.CaseSensitive),
  )
  assert_true(@path.path_equal("/a/./b", "/a/b", @path.CaseSensitive))
}

///|
test "ASCII-insensitive comparison applies to drives roots and components" {
  assert_true(
    @path.path_equal(
      "c:/Repo/Main.mbt",
      "C:/repo/main.MBT",
      @path.AsciiCaseInsensitive,
    ),
  )
  assert_true(
    @path.path_equal(
      "//HOST/Share/A",
      "//host/share/a",
      @path.AsciiCaseInsensitive,
    ),
  )
}

///|
test "relative to produces child sibling and parent routes" {
  assert_eq(@path.relative_to("/a/b/c", "/a", @path.CaseSensitive), Some("b/c"))
  assert_eq(
    @path.relative_to("/a/d", "/a/b/c", @path.CaseSensitive),
    Some("../../d"),
  )
  assert_eq(@path.relative_to("/a", "/a", @path.CaseSensitive), Some("."))
}

///|
test "relative to refuses unlike anchors and drives" {
  assert_eq(@path.relative_to("C:/a", "D:/a", @path.AsciiCaseInsensitive), None)
  assert_eq(@path.relative_to("/a", "a", @path.CaseSensitive), None)
  assert_eq(@path.relative_to("C:a", "C:/a", @path.AsciiCaseInsensitive), None)
}

///|
test "relative to uses its explicit case strategy" {
  assert_eq(
    @path.relative_to("/Repo/Src/Main", "/repo/src", @path.CaseSensitive),
    Some("../../Repo/Src/Main"),
  )
  assert_eq(
    @path.relative_to("/Repo/Src/Main", "/repo/src", @path.AsciiCaseInsensitive),
    Some("Main"),
  )
}

///|
test "within checks component boundaries rather than string prefixes" {
  assert_true(@path.is_within("/repo/src/a", "/repo/src", @path.CaseSensitive))
  assert_true(@path.is_within("/repo/src", "/repo/src", @path.CaseSensitive))
  assert_false(
    @path.is_within("/repo/source", "/repo/src", @path.CaseSensitive),
  )
  assert_false(
    @path.is_within("D:/repo", "C:/repo", @path.AsciiCaseInsensitive),
  )
}

///|
test "parsed parts are returned by defensive copy" {
  let parsed = @path.parse("/a/b")
  let parts = parsed.parts()
  parts.push("mutated")
  assert_eq(parsed.render(), "/a/b")
  assert_eq(parsed.root_name(), "/")
}
