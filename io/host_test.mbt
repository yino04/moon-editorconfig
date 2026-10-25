///|
test "host errors render operation path and message" {
  let error = @io.host_error("read", "a file", "access denied")
  assert_eq(error.render(), "read 'a file': access denied")
}

///|
async test "disk adapter reads repository UTF-8 bytes" {
  guard @io.read_utf8("examples/basic/.editorconfig") is Ok(text) else {
    fail("expected readable example")
  }
  assert_true(text.contains("root = true"))
  assert_true(text.contains("indent_size = 2"))
}

///|
async test "missing direct reads remain I/O errors" {
  guard @io.read_bytes("examples/does-not-exist.editorconfig") is Err(error) else {
    fail("expected missing-file error")
  }
  assert_eq(error.operation, "read")
  assert_true(error.path.contains("does-not-exist"))
}

///|
async test "disk discovery loads basic project config" {
  let loaded = @io.load_config_source("examples/basic/src/main.mbt")
  assert_eq(loaded.errors, [])
  assert_eq(loaded.diagnostics, [])
  assert_eq(loaded.source.file_count(), 1)
  assert_eq(loaded.discovered_paths, ["examples/basic/.editorconfig"])
}

///|
async test "disk discovery loads parent and child configs nearest first" {
  let loaded = @io.load_config_source("examples/nested/src/deep/main.mbt")
  assert_eq(loaded.errors, [])
  assert_eq(loaded.diagnostics, [])
  assert_eq(loaded.source.file_count(), 2)
  assert_eq(loaded.discovered_paths, [
    "examples/nested/src/.editorconfig", "examples/nested/.editorconfig",
  ])
}

///|
async test "missing config candidates are not failures" {
  let loaded = @io.load_config_source(
    "examples/windows-paths/project/src/deep/main.mbt",
  )
  assert_eq(loaded.errors, [])
  assert_eq(loaded.diagnostics, [])
  assert_eq(loaded.source.file_count(), 1)
}

///|
async test "custom config filename is supported" {
  let loaded = @io.load_config_source(
    "examples/basic/src/main.mbt",
    config_name="invalid.editorconfig",
  )
  assert_eq(loaded.errors, [])
  assert_eq(loaded.source.file_count(), 1)
  assert_eq(loaded.discovered_paths, ["examples/basic/invalid.editorconfig"])
}
