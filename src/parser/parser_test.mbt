///|
test "empty document parses without diagnostics" {
  let document = @parser.parse("", source="empty")
  assert_eq(document.preamble.length(), 0)
  assert_eq(document.sections.length(), 0)
  assert_eq(document.diagnostics.length(), 0)
}

///|
test "blank and comment-only document is empty" {
  let document = @parser.parse(" \t\n # comment\n;other\n")
  assert_eq(document.property_count(), 0)
  assert_eq(document.sections.length(), 0)
  assert_false(document.has_errors())
}

///|
test "preamble pair trims and lowercases key" {
  let document = @parser.parse("  RoOt \t= TRUE  ", source="preamble")
  assert_eq(document.preamble.length(), 1)
  let property = document.preamble[0]
  assert_eq(property.raw_key, "RoOt \t")
  assert_eq(property.key, "root")
  assert_eq(property.raw_value, " TRUE")
  assert_eq(property.value, "TRUE")
  assert_true(document.stops_search())
}

///|
test "pair may have an empty value" {
  let document = @parser.parse("custom =")
  assert_eq(document.preamble[0].value, "")
  assert_eq(document.preamble[0].raw_value, "")
  assert_false(document.has_errors())
}

///|
test "Unicode whitespace around pair fields is removed" {
  let document = @parser.parse("\u{00A0}Key\u{3000}=\u{2003}Value\u{00A0}")
  assert_eq(document.preamble[0].key, "key")
  assert_eq(document.preamble[0].value, "Value")
}

///|
test "first equal sign is the only separator" {
  let document = @parser.parse("command = a=b=c")
  assert_eq(document.preamble[0].key, "command")
  assert_eq(document.preamble[0].value, "a=b=c")
}

///|
test "hash and semicolon in values are not inline comments" {
  let document = @parser.parse("[*.txt]\nfoo = editorconfig ;) # literal")
  let property = document.sections[0].properties[0]
  assert_eq(property.value, "editorconfig ;) # literal")
  assert_eq(document.diagnostics.length(), 0)
}

///|
test "BOM and LF metadata flow into document" {
  let document = @parser.parse("\u{FEFF}root=true\n[*.mbt]\nindent_size=2\n")
  assert_true(document.has_bom)
  assert_eq(document.line_ending, @model.Lf)
  assert_eq(document.property_count(), 2)
}

///|
test "CRLF document parses all lines" {
  let document = @parser.parse("root=true\r\n[*]\r\nx=y")
  assert_eq(document.line_ending, @model.CrLf)
  assert_eq(document.sections.length(), 1)
  assert_eq(document.sections[0].properties[0].value, "y")
}

///|
test "simple section retains its glob" {
  let document = @parser.parse("[*.mbt]\nindent_size = 2")
  let section = document.sections[0]
  assert_eq(section.raw_glob, "*.mbt")
  assert_eq(section.glob, "*.mbt")
  assert_eq(section.properties.length(), 1)
}

///|
test "section span covers its complete source interval" {
  let document = @parser.parse(
    "[one]\nx=1\n# tail\n\n[two]\ny=2",
    source="spans",
  )
  let first = document.sections[0].span
  let second = document.sections[1].span
  assert_eq(first.start.line, 1)
  assert_eq(first.end.line, 5)
  assert_eq(second.start.line, 5)
  assert_eq(second.end.line, 6)
  assert_eq(second.end.column, 4)
}

///|
test "section header closes at final bracket" {
  let document = @parser.parse("[*.{html,[ch]}]\nindent_size=2")
  assert_eq(document.sections.length(), 1)
  assert_eq(document.sections[0].glob, "*.{html,[ch]}")
  assert_false(document.has_errors())
}

///|
test "nested square bracket spelling is not cut at first bracket" {
  let document = @parser.parse("[[ab][cd]]\nx=y")
  assert_eq(document.sections[0].glob, "[ab][cd]")
  assert_eq(document.sections[0].properties[0].key, "x")
}

///|
test "outer whitespace is removed before section recognition" {
  let document = @parser.parse(" \t [*.md] \t \n x = yes")
  assert_eq(document.sections.length(), 1)
  assert_eq(document.sections[0].glob, "*.md")
  assert_eq(document.sections[0].properties[0].value, "yes")
}

///|
test "whitespace inside brackets is section-name data" {
  let document = @parser.parse("[ *.md ]\nx=y")
  assert_eq(document.sections[0].raw_glob, " *.md ")
  assert_eq(document.sections[0].glob, " *.md ")
}

///|
test "duplicate properties preserve order" {
  let document = @parser.parse("[*]\nx=one\nx=two\nx=three")
  let properties = document.sections[0].properties
  assert_eq(properties.length(), 3)
  assert_eq(properties[0].value, "one")
  assert_eq(properties[2].value, "three")
  assert_eq(document.sections[0].last_property("X"), Some(properties[2]))
}

///|
test "duplicate sections remain distinct and ordered" {
  let document = @parser.parse("[*.mbt]\nx=1\n[*.mbt]\nx=2")
  assert_eq(document.sections.length(), 2)
  assert_eq(document.sections[0].ordinal, 0)
  assert_eq(document.sections[1].ordinal, 1)
  assert_eq(document.sections[1].properties[0].value, "2")
}

///|
test "preamble and section property ordinals share source order" {
  let document = @parser.parse("root=false\na=1\n[*]\nb=2\n[*.md]\nc=3")
  assert_eq(document.preamble[0].ordinal, 0)
  assert_eq(document.preamble[1].ordinal, 1)
  assert_eq(document.sections[0].properties[0].ordinal, 2)
  assert_eq(document.sections[1].properties[0].ordinal, 3)
}

///|
test "recovery reports invalid line and keeps later pair" {
  let document = @parser.parse("root=true\nthis is invalid\ncustom=ok")
  assert_eq(document.diagnostics.length(), 1)
  assert_eq(document.diagnostics[0].code, "EC2001")
  assert_eq(document.preamble.length(), 2)
  assert_eq(document.preamble[1].value, "ok")
}

///|
test "unclosed section discards its body until next section" {
  let document = @parser.parse("[broken\nskipped=yes\n[good]\nkept=yes")
  assert_eq(document.diagnostics[0].code, "EC2002")
  assert_eq(document.sections.length(), 1)
  assert_eq(document.sections[0].glob, "good")
  assert_eq(document.sections[0].properties.length(), 1)
  assert_eq(document.sections[0].properties[0].key, "kept")
}

///|
test "strict syntax mode stops after first error" {
  let options = @model.strict_parse_options()
  let document = @parser.parse("a=1\nbad line\nc=3\nother invalid", options~)
  assert_eq(document.preamble.length(), 1)
  assert_eq(document.diagnostics.length(), 1)
  assert_eq(document.diagnostics[0].code, "EC2001")
}

///|
test "empty key is invalid but later property recovers" {
  let document = @parser.parse(" = value\nvalid = yes")
  assert_eq(document.diagnostics[0].code, "EC2003")
  assert_eq(document.preamble.length(), 1)
  assert_eq(document.preamble[0].key, "valid")
  guard document.diagnostics[0].span is Some(span) else {
    fail("expected key diagnostic location")
  }
  assert_eq(span.start.line, 1)
}

///|
test "unknown custom value preserves case and interior whitespace" {
  let document = @parser.parse("[*]\nCustom_Key = Mixed  Case")
  let property = document.sections[0].properties[0]
  assert_eq(property.key, "custom_key")
  assert_eq(property.value, "Mixed  Case")
}

///|
test "key length limit counts Unicode scalar values" {
  let defaults = @model.default_limits()
  let limits = { ..defaults, max_key_length: 1, }
  let options = { ..@model.default_parse_options(), limits, }
  let document = @parser.parse("😀=ok", options~)
  assert_eq(document.preamble.length(), 1)
  assert_eq(document.diagnostics.length(), 0)
}

///|
test "overlong key has a precise resource diagnostic" {
  let defaults = @model.default_limits()
  let limits = { ..defaults, max_key_length: 3, }
  let options = { ..@model.default_parse_options(), limits, }
  let document = @parser.parse("four=value", options~)
  assert_eq(document.preamble.length(), 0)
  assert_eq(document.diagnostics[0].code, "EC2004")
  guard document.diagnostics[0].span is Some(span) else {
    fail("expected key limit span")
  }
  assert_eq(span.start.column, 1)
  assert_eq(span.end.column, 5)
}

///|
test "overlong value is rejected independently" {
  let defaults = @model.default_limits()
  let limits = { ..defaults, max_value_length: 3, }
  let options = { ..@model.default_parse_options(), limits, }
  let document = @parser.parse("key = four", options~)
  assert_eq(document.preamble.length(), 0)
  assert_eq(document.diagnostics[0].code, "EC2005")
}

///|
test "overlong glob is diagnosed and section body discarded" {
  let defaults = @model.default_limits()
  let limits = { ..defaults, max_glob_length: 3, }
  let options = { ..@model.default_parse_options(), limits, }
  let document = @parser.parse("[four]\nx=y\n[ok]\na=b", options~)
  assert_eq(document.diagnostics[0].code, "EC2006")
  assert_eq(document.sections.length(), 1)
  assert_eq(document.sections[0].glob, "ok")
}

///|
test "section count limit bounds retained nodes" {
  let defaults = @model.default_limits()
  let limits = { ..defaults, max_sections: 1, }
  let options = { ..@model.default_parse_options(), limits, }
  let document = @parser.parse("[one]\nx=1\n[two]\ny=2\n[three]\nz=3", options~)
  assert_eq(document.sections.length(), 1)
  assert_eq(document.sections[0].properties.length(), 1)
  assert_eq(document.diagnostics.length(), 1)
  assert_eq(document.diagnostics[0].code, "EC2007")
}

///|
test "property count limit includes preamble and section pairs" {
  let defaults = @model.default_limits()
  let limits = { ..defaults, max_properties: 2, }
  let options = { ..@model.default_parse_options(), limits, }
  let document = @parser.parse("root=true\n[*]\nx=1\ny=2\nz=3", options~)
  assert_eq(document.property_count(), 2)
  assert_eq(document.sections[0].properties.length(), 1)
  assert_eq(document.diagnostics[0].code, "EC2008")
}

///|
test "diagnostic count is bounded during recovery" {
  let defaults = @model.default_limits()
  let limits = { ..defaults, max_diagnostics: 2, }
  let options = { ..@model.default_parse_options(), limits, }
  let document = @parser.parse("bad\nworse\nstill bad\nlast bad", options~)
  assert_eq(document.diagnostics.length(), 2)
  assert_eq(document.error_count(), 2)
}

///|
test "strict lexical error returns only its first diagnostic" {
  let document = @parser.parse(
    "a=1\rb=2\rc=3",
    options=@model.strict_parse_options(),
  )
  assert_eq(document.preamble.length(), 0)
  assert_eq(document.diagnostics.length(), 1)
  assert_eq(document.diagnostics[0].code, "EC1003")
}

///|
test "rejecting BOM still permits recovery mode parsing" {
  let defaults = @model.default_parse_options()
  let options = { ..defaults, accept_bom: false, }
  let document = @parser.parse("\u{FEFF}root=true", options~)
  assert_eq(document.diagnostics[0].code, "EC1002")
  assert_eq(document.preamble.length(), 1)
  assert_true(document.stops_search())
}

///|
test "later preamble root value wins without deduplication" {
  let document = @parser.parse("root=false\nROOT=TRUE")
  assert_eq(document.preamble.length(), 2)
  assert_eq(document.root_value(), Some("TRUE"))
  assert_true(document.stops_search())
}

///|
test "properties after first section never return to preamble" {
  let document = @parser.parse("root=true\n[*]\nx=1\nroot=false")
  assert_eq(document.preamble.length(), 1)
  assert_eq(document.sections[0].properties.length(), 2)
  assert_eq(document.root_value(), Some("true"))
}

///|
test "checked API distinguishes clean and invalid documents" {
  guard @parser.parse_checked("root=true") is Ok(clean) else {
    fail("expected clean parse")
  }
  assert_eq(clean.preamble.length(), 1)
  guard @parser.parse_checked("not a pair") is Err(diagnostics) else {
    fail("expected checked parse failure")
  }
  assert_eq(diagnostics[0].code, "EC2001")
}

///|
test "mixed valid line separators remain syntactically valid" {
  let document = @parser.parse("root=true\n[*]\r\nx=y")
  assert_eq(document.line_ending, @model.Mixed)
  assert_eq(document.diagnostics.length(), 0)
  assert_eq(document.property_count(), 2)
}

///|
test "empty section name is preserved as specified data" {
  let document = @parser.parse("[]\nx=y")
  assert_eq(document.sections.length(), 1)
  assert_eq(document.sections[0].glob, "")
  assert_eq(document.sections[0].properties.length(), 1)
}

///|
test "trailing text makes an intended section header invalid" {
  let document = @parser.parse("[*.mbt] # not inline comment\nx=y")
  assert_eq(document.sections.length(), 0)
  assert_eq(document.diagnostics[0].code, "EC2002")
  assert_eq(document.property_count(), 0)
}

///|
test "byte parser rejects invalid UTF-8 before syntax parsing" {
  guard @parser.parse_utf8(b"root=true\n\xC0\xAF") is Err(diagnostic) else {
    fail("expected invalid UTF-8")
  }
  assert_eq(diagnostic.code, "EC1005")
}

///|
test "byte parser accepts non-ASCII UTF-8 keys and values" {
  guard @parser.parse_utf8(b"[*.txt]\nlabel=\xE4\xB8\xAD\xE6\x96\x87")
    is Ok(document) else {
    fail("expected valid UTF-8")
  }
  assert_eq(document.sections[0].properties[0].value, "中文")
}
