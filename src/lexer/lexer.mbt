///|
/// The physical terminator attached to a source line. `BareCr` is retained so
/// recovery can continue at the next line while still reporting the invalid
/// separator required by EditorConfig 0.17.2.
pub(all) enum PhysicalLineEnding {
  NoEnding
  LfEnding
  CrLfEnding
  BareCrEnding
} derive(Eq, @debug.Debug)

///|
/// Classification performed after the specification-mandated removal of
/// leading and trailing whitespace.
pub(all) enum LexLineKind {
  BlankLine
  CommentLine
  ContentLine
} derive(Eq, @debug.Debug)

///|
/// A physical line without its line terminator. `raw` excludes a leading UTF-8
/// BOM on the first line; `text` is the whitespace-trimmed view materialized
/// as a String. Spans use UTF-16 code-unit offsets, matching MoonBit String.
pub struct LexLine {
  raw : String
  text : String
  kind : LexLineKind
  span : @model.SourceSpan
  content_span : @model.SourceSpan
  number : Int32
  ending : PhysicalLineEnding
} derive(Eq, @debug.Debug)

///|
/// Complete bounded lexer output. Syntax is intentionally left to the parser;
/// this phase is responsible for physical lines, BOMs, whitespace, comments,
/// source coordinates, and line-ending diagnostics.
pub struct LexResult {
  lines : Array[LexLine]
  diagnostics : Array[@model.Diagnostic]
  has_bom : Bool
  line_ending : @model.LineEnding
  truncated : Bool
} derive(Eq, @debug.Debug)

///|
fn is_trim_whitespace(unit : UInt16) -> Bool {
  unit.to_int().unsafe_to_char().is_whitespace()
}

///|
fn trim_bounds(value : String) -> (Int32, Int32) {
  let mut start = 0
  let mut finish = value.length()
  while start < finish && is_trim_whitespace(value[start]) {
    start += 1
  }
  while finish > start && is_trim_whitespace(value[finish - 1]) {
    finish -= 1
  }
  (start, finish)
}

///|
fn classify(text : String) -> LexLineKind {
  if text.length() == 0 {
    BlankLine
  } else if text[0] == 0x23 || text[0] == 0x3B {
    CommentLine
  } else {
    ContentLine
  }
}

///|
fn ending_width(ending : PhysicalLineEnding) -> Int32 {
  match ending {
    NoEnding => 0
    LfEnding | BareCrEnding => 1
    CrLfEnding => 2
  }
}

///|
fn make_span(
  source : String,
  start_offset : Int32,
  end_offset : Int32,
  line : Int32,
  start_column : Int32,
  end_column : Int32,
) -> @model.SourceSpan {
  @model.source_span(
    source,
    @model.source_pos(start_offset, line, start_column),
    @model.source_pos(end_offset, line, end_column),
  )
}

///|
fn push_diagnostic(
  diagnostics : Array[@model.Diagnostic],
  limit : Int32,
  diagnostic : @model.Diagnostic,
) -> Unit {
  if diagnostics.length() < limit {
    diagnostics.push(diagnostic)
  }
}

///|
fn scan_embedded_boms(
  raw : String,
  source : String,
  raw_offset : Int32,
  line : Int32,
  diagnostics : Array[@model.Diagnostic],
  diagnostic_limit : Int32,
) -> Unit {
  for index = 0; index < raw.length(); index = index + 1 {
    if raw[index] == 0xFEFF {
      let span = make_span(
        source,
        raw_offset + index,
        raw_offset + index + 1,
        line,
        index + 1,
        index + 2,
      )
      push_diagnostic(
        diagnostics,
        diagnostic_limit,
        @model.error_diagnostic(
          "EC1004",
          "a byte-order mark is only permitted at the start of the document",
          span~,
          suggestion="remove the embedded BOM",
        ),
      )
    }
  }
}

///|
fn push_line(
  lines : Array[LexLine],
  diagnostics : Array[@model.Diagnostic],
  text : String,
  source : String,
  start : Int32,
  finish : Int32,
  line : Int32,
  ending : PhysicalLineEnding,
  diagnostic_limit : Int32,
) -> Unit {
  let raw = text[start:finish].to_owned()
  scan_embedded_boms(raw, source, start, line, diagnostics, diagnostic_limit)
  let (trim_start, trim_finish) = trim_bounds(raw)
  let normalized = raw[trim_start:trim_finish].to_owned()
  let span_end = match ending {
    NoEnding => @model.source_pos(finish, line, raw.length() + 1)
    LfEnding | CrLfEnding | BareCrEnding =>
      @model.source_pos(finish + ending_width(ending), line + 1, 1)
  }
  let span = @model.source_span(
    source,
    @model.source_pos(start, line, 1),
    span_end,
  )
  let content_span = make_span(
    source,
    start + trim_start,
    start + trim_finish,
    line,
    trim_start + 1,
    trim_finish + 1,
  )
  lines.push({
    raw,
    text: normalized,
    kind: classify(normalized),
    span,
    content_span,
    number: line,
    ending,
  })
}

///|
/// Split an EditorConfig String into bounded physical lines. The input String
/// is already valid Unicode; byte-oriented callers can use `lex_utf8` for
/// strict UTF-8 validation before scanning.
pub fn lex(
  text : String,
  source~ : String = "<memory>",
  limits~ : @model.ResourceLimits = @model.default_limits(),
  accept_bom~ : Bool = true,
) -> LexResult {
  let lines : Array[LexLine] = []
  let diagnostics : Array[@model.Diagnostic] = []
  if text.length() > limits.max_document_length {
    push_diagnostic(
      diagnostics,
      limits.max_diagnostics,
      @model.error_diagnostic(
        "EC1001",
        "document length exceeds the configured parsing limit",
        span=@model.unknown_span(source),
        suggestion="raise max_document_length only for trusted input",
      ),
    )
    return {
      lines,
      diagnostics,
      has_bom: text.length() > 0 && text[0] == 0xFEFF,
      line_ending: @model.None,
      truncated: true,
    }
  }
  let has_bom = text.length() > 0 && text[0] == 0xFEFF
  if has_bom && !accept_bom {
    push_diagnostic(
      diagnostics,
      limits.max_diagnostics,
      @model.error_diagnostic(
        "EC1002",
        "a byte-order mark is disabled by the parse options",
        span=make_span(source, 0, 1, 1, 1, 2),
        suggestion="remove the BOM or enable accept_bom",
      ),
    )
  }
  let mut cursor = if has_bom { 1 } else { 0 }
  let mut line_start = cursor
  let mut line_number = 1
  let mut lf_count = 0
  let mut crlf_count = 0
  let mut bare_cr_count = 0
  while cursor < text.length() {
    let unit = text[cursor]
    if unit == 0x0A {
      push_line(
        lines,
        diagnostics,
        text,
        source,
        line_start,
        cursor,
        line_number,
        LfEnding,
        limits.max_diagnostics,
      )
      lf_count += 1
      cursor += 1
      line_start = cursor
      line_number += 1
    } else if unit == 0x0D {
      if cursor + 1 < text.length() && text[cursor + 1] == 0x0A {
        push_line(
          lines,
          diagnostics,
          text,
          source,
          line_start,
          cursor,
          line_number,
          CrLfEnding,
          limits.max_diagnostics,
        )
        crlf_count += 1
        cursor += 2
      } else {
        push_line(
          lines,
          diagnostics,
          text,
          source,
          line_start,
          cursor,
          line_number,
          BareCrEnding,
          limits.max_diagnostics,
        )
        bare_cr_count += 1
        push_diagnostic(
          diagnostics,
          limits.max_diagnostics,
          @model.error_diagnostic(
            "EC1003",
            "bare carriage return is not a valid EditorConfig line separator",
            span=make_span(
              source,
              cursor,
              cursor + 1,
              line_number,
              cursor - line_start + 1,
              cursor - line_start + 2,
            ),
            suggestion="use LF or CRLF line separators",
          ),
        )
        cursor += 1
      }
      line_start = cursor
      line_number += 1
    } else {
      cursor += 1
    }
  }
  if line_start < text.length() {
    push_line(
      lines,
      diagnostics,
      text,
      source,
      line_start,
      text.length(),
      line_number,
      NoEnding,
      limits.max_diagnostics,
    )
  }
  let styles = (if lf_count > 0 { 1 } else { 0 }) +
    (if crlf_count > 0 { 1 } else { 0 }) +
    (if bare_cr_count > 0 { 1 } else { 0 })
  let line_ending = if styles == 0 {
    @model.None
  } else if styles > 1 || bare_cr_count > 0 {
    @model.Mixed
  } else if lf_count > 0 {
    @model.Lf
  } else {
    @model.CrLf
  }
  { lines, diagnostics, has_bom, line_ending, truncated: false, }
}

///|
/// Strictly decode UTF-8 bytes without discarding the BOM. Keeping U+FEFF in
/// the decoded String lets `lex` apply the caller's BOM policy consistently.
pub fn decode_utf8(
  bytes : BytesView,
  source~ : String = "<memory>",
) -> Result[String, @model.Diagnostic] {
  let decoded = @utf8.decode(bytes) catch {
    _ =>
      return Err(
        @model.error_diagnostic(
          "EC1005",
          "input is not well-formed UTF-8",
          span=@model.unknown_span(source),
          suggestion="decode or transcode the file as strict UTF-8",
        ),
      )
  }
  Ok(decoded)
}

///|
/// Byte-oriented lexer entry point for file-system adapters. Malformed UTF-8
/// is rejected rather than silently replaced with U+FFFD.
pub fn lex_utf8(
  bytes : BytesView,
  source~ : String = "<memory>",
  limits~ : @model.ResourceLimits = @model.default_limits(),
  accept_bom~ : Bool = true,
) -> Result[LexResult, @model.Diagnostic] {
  match decode_utf8(bytes, source~) {
    Err(diagnostic) => Err(diagnostic)
    Ok(text) => Ok(lex(text, source~, limits~, accept_bom~))
  }
}

///|
pub extend PhysicalLineEnding with Eq::{not_equal, equal}

///|
pub extend PhysicalLineEnding with @debug.Debug::{to_repr}

///|
pub extend LexLineKind with Eq::{not_equal, equal}

///|
pub extend LexLineKind with @debug.Debug::{to_repr}

///|
pub extend LexLine with Eq::{not_equal, equal}

///|
pub extend LexLine with @debug.Debug::{to_repr}

///|
pub extend LexResult with Eq::{not_equal, equal}

///|
pub extend LexResult with @debug.Debug::{to_repr}
