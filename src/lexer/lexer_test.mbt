///|
test "empty input has no physical lines" {
  let result = @lexer.lex("", source="empty")
  assert_eq(result.lines.length(), 0)
  assert_eq(result.line_ending, @model.None)
  assert_false(result.has_bom)
}

///|
test "leading BOM is removed from first line" {
  let result = @lexer.lex("\u{FEFF}root=true\n", source="bom")
  assert_true(result.has_bom)
  assert_eq(result.lines.length(), 1)
  assert_eq(result.lines[0].raw, "root=true")
  assert_eq(result.lines[0].content_span.start.offset, 1)
}

///|
test "LF input does not create a phantom trailing line" {
  let result = @lexer.lex("one\ntwo\n")
  assert_eq(result.lines.length(), 2)
  assert_eq(result.lines[0].ending, @lexer.LfEnding)
  assert_eq(result.lines[1].ending, @lexer.LfEnding)
  assert_eq(result.line_ending, @model.Lf)
}

///|
test "CRLF is retained as one physical terminator" {
  let result = @lexer.lex("one\r\ntwo\r\n")
  assert_eq(result.lines.length(), 2)
  assert_eq(result.lines[0].ending, @lexer.CrLfEnding)
  assert_eq(result.lines[1].span.end.offset, 10)
  assert_eq(result.line_ending, @model.CrLf)
}

///|
test "mixed LF and CRLF is reported in metadata" {
  let result = @lexer.lex("one\ntwo\r\nthree")
  assert_eq(result.line_ending, @model.Mixed)
  assert_eq(result.lines.length(), 3)
  assert_eq(result.diagnostics.length(), 0)
}

///|
test "unterminated final line is preserved" {
  let result = @lexer.lex("one\ntwo")
  assert_eq(result.lines.length(), 2)
  assert_eq(result.lines[1].raw, "two")
  assert_eq(result.lines[1].ending, @lexer.NoEnding)
}

///|
test "horizontal whitespace makes a blank line" {
  let result = @lexer.lex(" \t  \n")
  assert_eq(result.lines[0].kind, @lexer.BlankLine)
  assert_eq(result.lines[0].text, "")
  assert_true(result.lines[0].content_span.is_empty())
}

///|
test "Unicode whitespace is trimmed before line classification" {
  let result = @lexer.lex("\u{00A0}# comment\u{3000}\n")
  assert_eq(result.lines[0].kind, @lexer.CommentLine)
  assert_eq(result.lines[0].text, "# comment")
}

///|
test "first non-whitespace hash and semicolon start comments" {
  let result = @lexer.lex("  # first\n\t; second\n")
  assert_eq(result.lines[0].kind, @lexer.CommentLine)
  assert_eq(result.lines[0].text, "# first")
  assert_eq(result.lines[1].kind, @lexer.CommentLine)
}

///|
test "comment markers later in a line remain content" {
  let result = @lexer.lex("key = value # literal ; text")
  assert_eq(result.lines[0].kind, @lexer.ContentLine)
  assert_eq(result.lines[0].text, "key = value # literal ; text")
}

///|
test "BOM can be rejected by options while recovering line" {
  let result = @lexer.lex("\u{FEFF}root=true", accept_bom=false)
  assert_eq(result.diagnostics.length(), 1)
  assert_eq(result.diagnostics[0].code, "EC1002")
  assert_eq(result.lines[0].raw, "root=true")
}

///|
test "embedded BOM produces a located diagnostic" {
  let result = @lexer.lex("a=1\nx=\u{FEFF}bad", source="embedded")
  assert_eq(result.diagnostics.length(), 1)
  assert_eq(result.diagnostics[0].code, "EC1004")
  guard result.diagnostics[0].span is Some(span) else {
    fail("expected located BOM diagnostic")
  }
  assert_eq(span.start.line, 2)
  assert_eq(span.start.column, 3)
}

///|
test "bare CR is a recovery boundary and an error" {
  let result = @lexer.lex("one\rtwo")
  assert_eq(result.lines.length(), 2)
  assert_eq(result.lines[0].ending, @lexer.BareCrEnding)
  assert_eq(result.diagnostics[0].code, "EC1003")
  assert_eq(result.line_ending, @model.Mixed)
}

///|
test "content coordinates account for trim and CRLF" {
  let result = @lexer.lex("  key=x  \r\n", source="coords")
  let span = result.lines[0].content_span
  assert_eq(span.start.offset, 2)
  assert_eq(span.start.column, 3)
  assert_eq(span.end.offset, 7)
  assert_eq(result.lines[0].span.end.line, 2)
}

///|
test "document limit prevents partial parsing" {
  let defaults = @model.default_limits()
  let limits = { ..defaults, max_document_length: 3, }
  let result = @lexer.lex("four", limits~)
  assert_true(result.truncated)
  assert_eq(result.lines.length(), 0)
  assert_eq(result.diagnostics[0].code, "EC1001")
}

///|
test "diagnostic limit bounds hostile repeated input" {
  let defaults = @model.default_limits()
  let limits = { ..defaults, max_diagnostics: 2, }
  let result = @lexer.lex("a\rb\rc\rd", limits~)
  assert_eq(result.lines.length(), 4)
  assert_eq(result.diagnostics.length(), 2)
}

///|
test "byte entry point rejects malformed UTF-8" {
  guard @lexer.lex_utf8(b"valid\xFFtail", source="bytes") is Err(diagnostic) else {
    fail("expected strict UTF-8 rejection")
  }
  assert_eq(diagnostic.code, "EC1005")
  assert_eq(diagnostic.location_label(), "bytes:1:1")
}

///|
test "byte entry point preserves UTF-8 BOM policy" {
  guard @lexer.lex_utf8(b"\xEF\xBB\xBFroot=true") is Ok(result) else {
    fail("expected valid UTF-8")
  }
  assert_true(result.has_bom)
  assert_eq(result.lines[0].text, "root=true")
}
