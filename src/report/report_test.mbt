///|
fn test_span() -> @model.SourceSpan {
  @model.source_span(
    "a\"b.editorconfig",
    @model.source_pos(3, 2, 4),
    @model.source_pos(8, 2, 9),
  )
}

///|
test "positions have stable field order" {
  let output = @report.position_json(@model.source_pos(3, 2, 4))
  assert_eq(output, "{\"offset\":3,\"line\":2,\"column\":4}")
}

///|
test "spans escape source names as JSON strings" {
  let output = @report.span_json(test_span())
  assert_true(output.contains("\"source\":\"a\\\"b.editorconfig\""))
  ignore(@json.parse(output))
}

///|
test "diagnostic JSON emits null optional fields" {
  let diagnostic = @model.error_diagnostic("E_TEST", "broken")
  let output = @report.diagnostic_json(diagnostic)
  assert_true(output.contains("\"suggestion\":null"))
  assert_true(output.contains("\"span\":null"))
  ignore(@json.parse(output))
}

///|
test "diagnostic JSON includes locations and suggestions" {
  let diagnostic = @model.warning_diagnostic(
    "W_TEST",
    "odd",
    span=test_span(),
    suggestion="change it",
  )
  let output = @report.diagnostic_json(diagnostic)
  assert_true(output.contains("\"severity\":\"warning\""))
  assert_true(output.contains("\"suggestion\":\"change it\""))
  ignore(@json.parse(output))
}

///|
test "property JSON preserves raw and normalized forms" {
  let property = @model.property(
    "Indent_Size",
    "indent_size",
    " 2 ",
    "2",
    test_span(),
    7,
  )
  let output = @report.property_json(property)
  assert_true(output.contains("\"rawKey\":\"Indent_Size\""))
  assert_true(output.contains("\"key\":\"indent_size\""))
  assert_true(output.contains("\"ordinal\":7"))
  ignore(@json.parse(output))
}

///|
test "document JSON preserves section and property order" {
  let first = @model.property("a", "a", "1", "1", test_span(), 0)
  let second = @model.property("b", "b", "2", "2", test_span(), 1)
  let section = @model.section(
    "*.mbt",
    "*.mbt",
    [first, second],
    test_span(),
    0,
  )
  let document = @model.document("demo", [], [section], [], false, @model.Lf)
  let output = @report.document_json(document)
  guard output.find("\"key\":\"a\"") is Some(a) else { fail("missing a") }
  guard output.find("\"key\":\"b\"") is Some(b) else { fail("missing b") }
  assert_true(a < b)
  ignore(@json.parse(output))
}

///|
test "document JSON is deterministic" {
  let document = @model.empty_document("memory")
  assert_eq(@report.document_json(document), @report.document_json(document))
  assert_true(
    @report.document_json(document).contains("\"specVersion\":\"0.17.2\""),
  )
}

///|
test "settings JSON includes source trace in order" {
  let span = test_span()
  let property = @model.effective_property(
    "indent_size", "2", "/.editorconfig", "*.mbt", span,
  )
  let assigned = @model.trace_event(
    @model.Assign,
    "indent_size",
    "4",
    "/.editorconfig",
    "*.mbt",
    span,
    "initial assignment",
  )
  let overridden = @model.trace_event(
    @model.Override,
    "indent_size",
    "2",
    "/src/.editorconfig",
    "*.mbt",
    span,
    "closer configuration",
  )
  let settings : @model.EffectiveSettings = {
    target_path: "/src/main.mbt",
    properties: [property],
    diagnostics: [],
    trace: [assigned, overridden],
  }
  let output = @report.settings_json(settings)
  guard output.find("\"action\":\"assign\"") is Some(first) else {
    fail("missing assignment")
  }
  guard output.find("\"action\":\"override\"") is Some(second) else {
    fail("missing override")
  }
  assert_true(first < second)
  ignore(@json.parse(output))
}

///|
test "human diagnostic includes location code and help" {
  let diagnostic = @model.error_diagnostic(
    "E_DEMO",
    "bad value",
    span=test_span(),
    suggestion="use a valid value",
  )
  let output = @report.diagnostic_text(diagnostic)
  assert_true(output.contains("a\"b.editorconfig:2:4"))
  assert_true(output.contains("error [E_DEMO]"))
  assert_true(output.contains("help: use a valid value"))
}

///|
test "human settings remain stable and readable" {
  let property = @model.effective_property(
    "end_of_line",
    "lf",
    "/.editorconfig",
    "*",
    test_span(),
  )
  let settings : @model.EffectiveSettings = {
    target_path: "/main.mbt",
    properties: [property],
    diagnostics: [],
    trace: [],
  }
  assert_eq(
    @report.settings_text(settings),
    "end_of_line=lf # /.editorconfig [*]",
  )
}
