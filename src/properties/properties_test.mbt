///|
fn make_property(
  key : String,
  value : String,
  ordinal~ : Int32 = 0,
) -> @model.Property {
  @model.property(
    key,
    key.to_lower(),
    value,
    value,
    @model.unknown_span("test.editorconfig"),
    ordinal,
  )
}

///|
test "known property list is complete for specification 0.17.2" {
  let names = @properties.known_property_names()
  assert_eq(names.length(), 9)
  assert_true(@properties.is_known_property("INDENT_SIZE"))
  assert_true(@properties.is_known_property("spelling_language"))
  assert_false(@properties.is_known_property("custom_key"))
}

///|
test "indent style accepts tab and space without case sensitivity" {
  let tab = @properties.validate_property(make_property("indent_style", "TAB"))
  let space = @properties.validate_property(
    make_property("indent_style", "space"),
  )
  assert_true(tab.is_valid())
  assert_eq(tab.normalized_value, "tab")
  assert_eq(space.normalized_value, "space")
}

///|
test "indent style rejects arbitrary values" {
  let result = @properties.validate_property(
    make_property("indent_style", "mixed"),
  )
  assert_false(result.is_valid())
  assert_true(result.diagnostic is Some(_))
}

///|
test "indent size accepts positive integers and tab" {
  assert_true(
    @properties.validate_property(make_property("indent_size", "1")).is_valid(),
  )
  assert_true(
    @properties.validate_property(make_property("indent_size", "128")).is_valid(),
  )
  assert_true(
    @properties.validate_property(make_property("indent_size", "TAB")).is_valid(),
  )
}

///|
test "indent size rejects zero negative and fractional values" {
  for value in ["0", "-1", "1.5", "two", ""] {
    assert_false(
      @properties.validate_property(make_property("indent_size", value)).is_valid(),
    )
  }
}

///|
test "tab width must be a positive whole number" {
  assert_true(
    @properties.validate_property(make_property("tab_width", "4")).is_valid(),
  )
  assert_false(
    @properties.validate_property(make_property("tab_width", "0")).is_valid(),
  )
  assert_false(
    @properties.validate_property(make_property("tab_width", "tab")).is_valid(),
  )
}

///|
test "end of line accepts the three standard values" {
  for value in ["LF", "cr", "CrLf"] {
    assert_true(
      @properties.validate_property(make_property("end_of_line", value)).is_valid(),
    )
  }
  assert_false(
    @properties.validate_property(make_property("end_of_line", "native")).is_valid(),
  )
}

///|
test "charset validates the normative list" {
  for value in ["latin1", "utf-8", "utf-8-bom", "utf-16be", "UTF-16LE"] {
    assert_true(
      @properties.validate_property(make_property("charset", value)).is_valid(),
    )
  }
  assert_false(
    @properties.validate_property(make_property("charset", "ascii")).is_valid(),
  )
}

///|
test "boolean properties accept only true and false" {
  for key in ["trim_trailing_whitespace", "insert_final_newline"] {
    assert_true(
      @properties.validate_property(make_property(key, "TRUE")).is_valid(),
    )
    assert_true(
      @properties.validate_property(make_property(key, "false")).is_valid(),
    )
    assert_false(
      @properties.validate_property(make_property(key, "yes")).is_valid(),
    )
  }
}

///|
test "spelling language accepts two-letter and language-territory forms" {
  let simple = @properties.validate_property(
    make_property("spelling_language", "EN"),
  )
  let regional = @properties.validate_property(
    make_property("spelling_language", "zh-cn"),
  )
  assert_eq(simple.normalized_value, "en")
  assert_eq(regional.normalized_value, "zh-CN")
}

///|
test "spelling language rejects malformed tags" {
  for value in ["e", "eng", "en_US", "en-USA", "12", "en-1A"] {
    assert_false(
      @properties.validate_property(make_property("spelling_language", value)).is_valid(),
    )
  }
}

///|
test "unset is accepted for every known and custom pair" {
  for key in ["indent_size", "charset", "custom_key"] {
    let result = @properties.validate_property(make_property(key, "UnSeT"))
    assert_true(result.is_valid())
    assert_eq(result.status, @properties.Unset)
  }
}

///|
test "unknown custom keys are retained exactly" {
  let result = @properties.validate_property(
    make_property("custom_key", "Value # 1"),
  )
  assert_true(result.is_valid())
  assert_true(result.is_custom())
  assert_eq(result.normalized_value, "Value # 1")
}

///|
test "root is valid only in the preamble" {
  let root = make_property("root", "TRUE")
  assert_true(@properties.validate_property(root, in_preamble=true).is_valid())
  let section_result = @properties.validate_property(root)
  assert_false(section_result.is_valid())
  guard section_result.diagnostic is Some(diag) else {
    fail("expected diagnostic")
  }
  assert_eq(diag.code, "E_ROOT_LOCATION")
}

///|
test "root rejects non-boolean preamble values" {
  assert_false(
    @properties.validate_property(
      make_property("root", "yes"),
      in_preamble=true,
    ).is_valid(),
  )
}

///|
test "document validation reports ignored preamble pairs" {
  let prop = make_property("indent_size", "2")
  let doc = @model.document("test", [prop], [], [], false, @model.None)
  let diagnostics = @properties.validate_document(doc)
  assert_eq(diagnostics.length(), 1)
  assert_eq(diagnostics[0].code, "W_PREAMBLE_IGNORED")
}

///|
test "document validation reports duplicate pairs" {
  let span = @model.unknown_span("test")
  let section = @model.section(
    "*",
    "*",
    [
      make_property("indent_size", "2"),
      make_property("indent_size", "4", ordinal=1),
    ],
    span,
    0,
  )
  let doc = @model.document("test", [], [section], [], false, @model.None)
  let diagnostics = @properties.validate_document(doc)
  assert_eq(diagnostics.length(), 1)
  assert_eq(diagnostics[0].code, "W_DUPLICATE_PROPERTY")
}

///|
test "numeric indent size supplies default tab width" {
  let semantics = @properties.indentation_semantics([
    make_property("indent_style", "space"),
    make_property("indent_size", "2"),
  ])
  assert_eq(semantics.indent_style, Some("space"))
  assert_eq(semantics.indent_size, Some(2))
  assert_eq(semantics.tab_width, Some(2))
  assert_false(semantics.indent_size_uses_tab)
}

///|
test "explicit tab width overrides the derived width" {
  let semantics = @properties.indentation_semantics([
    make_property("indent_size", "4"),
    make_property("tab_width", "8"),
  ])
  assert_eq(semantics.indent_size, Some(4))
  assert_eq(semantics.tab_width, Some(8))
}

///|
test "indent size tab derives from configured tab width" {
  let semantics = @properties.indentation_semantics([
    make_property("indent_size", "tab"),
    make_property("tab_width", "3"),
  ])
  assert_eq(semantics.indent_size, Some(3))
  assert_eq(semantics.tab_width, Some(3))
  assert_true(semantics.indent_size_uses_tab)
  assert_false(semantics.uses_editor_tab_width)
}

///|
test "indent size tab can defer to the editor" {
  let semantics = @properties.indentation_semantics([
    make_property("indent_size", "tab"),
  ])
  assert_eq(semantics.indent_size, None)
  assert_true(semantics.uses_editor_tab_width)
}

///|
test "later unset removes indentation values" {
  let semantics = @properties.indentation_semantics([
    make_property("indent_size", "2"),
    make_property("indent_size", "unset", ordinal=1),
  ])
  assert_eq(semantics.indent_size, None)
  assert_eq(semantics.tab_width, None)
}

///|
test "normalized property preserves raw spelling and source metadata" {
  let original = make_property("CHARSET", "UTF-8")
  let normalized = @properties.normalized_property(original)
  assert_eq(normalized.raw_key, "CHARSET")
  assert_eq(normalized.key, "charset")
  assert_eq(normalized.raw_value, "UTF-8")
  assert_eq(normalized.value, "utf-8")
}
