///|
test "source positions advance without becoming negative" {
  let origin = @model.source_origin()
  assert_eq(origin.offset, 0)
  assert_eq(origin.line, 1)
  assert_eq(origin.column, 1)
  let next = origin.next_column(width=3)
  assert_eq(next.offset, 3)
  assert_eq(next.column, 4)
  let unchanged = next.next_column(width=-3)
  assert_eq(unchanged, next)
}

///|
test "source span is half open" {
  let start = @model.source_pos(2, 1, 3)
  let finish = @model.source_pos(5, 1, 6)
  let span = @model.source_span("demo", start, finish)
  assert_false(span.is_empty())
  assert_true(span.contains_offset(2))
  assert_true(span.contains_offset(4))
  assert_false(span.contains_offset(5))
}

///|
test "property normalization helpers retain raw spelling" {
  let span = @model.unknown_span("demo")
  let prop = @model.property(
    "Indent_Size", "indent_size", " UnSet ", "unset", span, 0,
  )
  assert_eq(prop.raw_key, "Indent_Size")
  assert_eq(prop.raw_value, " UnSet ")
  assert_true(prop.is_unset())
  assert_false(prop.is_root())
}

///|
test "section last property observes source order" {
  let span = @model.unknown_span("demo")
  let one = @model.property("x", "x", "1", "1", span, 0)
  let two = @model.property("x", "x", "2", "2", span, 1)
  let section = @model.section("*", "*", [one, two], span, 0)
  guard section.last_property("X") is Some(prop) else {
    fail("expected property")
  }
  assert_eq(prop.value, "2")
}

///|
test "document root uses the latest preamble pair" {
  let span = @model.unknown_span("demo")
  let first = @model.property("root", "root", "false", "false", span, 0)
  let second = @model.property("ROOT", "root", "TRUE", "true", span, 1)
  let doc = @model.document("demo", [first, second], [], [], false, @model.Lf)
  assert_eq(doc.root_value(), Some("true"))
  assert_true(doc.stops_search())
  assert_eq(doc.property_count(), 2)
}

///|
test "diagnostics distinguish errors and warnings" {
  let error = @model.error_diagnostic("E001", "bad", suggestion="fix")
  let warning = @model.warning_diagnostic("W001", "odd")
  let doc = @model.document(
    "demo",
    [],
    [],
    [error, warning],
    false,
    @model.None,
  )
  assert_true(doc.has_errors())
  assert_eq(doc.error_count(), 1)
  assert_eq(doc.warning_count(), 1)
  assert_eq(error.location_label(), "<unknown>")
}

///|
test "default limits cover all specification minima" {
  let limits = @model.default_limits()
  assert_true(limits.is_valid())
  assert_true(limits.max_key_length >= 1024)
  assert_true(limits.max_value_length >= 4096)
  assert_true(limits.max_glob_length >= 1024)
}

///|
test "effective settings perform case-insensitive lookup" {
  let span = @model.unknown_span("/.editorconfig")
  let prop : @model.EffectiveProperty = {
    key: "indent_size",
    value: "2",
    config_path: "/.editorconfig",
    section_glob: "*.mbt",
    span,
  }
  let settings : @model.EffectiveSettings = {
    target_path: "/src/main.mbt",
    properties: [prop],
    diagnostics: [],
    trace: [],
  }
  assert_eq(settings.value("INDENT_SIZE"), Some("2"))
  assert_eq(settings.value("missing"), None)
}
