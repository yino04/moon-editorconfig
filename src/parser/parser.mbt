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
fn first_equals(value : String) -> Int32? {
  for index = 0; index < value.length(); index = index + 1 {
    if value[index] == 0x3D {
      return Some(index)
    }
  }
  None
}

///|
fn subspan(
  line : @lexer.LexLine,
  start : Int32,
  finish : Int32,
) -> @model.SourceSpan {
  @model.source_span(
    line.content_span.source,
    @model.source_pos(
      line.content_span.start.offset + start,
      line.number,
      line.content_span.start.column + start,
    ),
    @model.source_pos(
      line.content_span.start.offset + finish,
      line.number,
      line.content_span.start.column + finish,
    ),
  )
}

///|
fn append_diagnostic(
  diagnostics : Array[@model.Diagnostic],
  options : @model.ParseOptions,
  diagnostic : @model.Diagnostic,
) -> Bool {
  if diagnostics.length() < options.limits.max_diagnostics {
    diagnostics.push(diagnostic)
  }
  options.mode == @model.Strict && diagnostic.is_error()
}

///|
fn extend_section_span(
  sections : Array[@model.Section],
  current_section_index : Int32?,
  line : @lexer.LexLine,
) -> Unit {
  match current_section_index {
    None => ()
    Some(index) => {
      let section = sections[index]
      sections[index] = { ..section, span: section.span.merge(line.span), }
    }
  }
}

///|
fn invalid_line_diagnostic(line : @lexer.LexLine) -> @model.Diagnostic {
  @model.error_diagnostic(
    "EC2001",
    "line is neither a section header nor a key-value pair",
    span=line.content_span,
    suggestion="use [glob] or key = value",
  )
}

///|
fn unclosed_section_diagnostic(line : @lexer.LexLine) -> @model.Diagnostic {
  @model.error_diagnostic(
    "EC2002",
    "section header must end with a closing bracket",
    span=line.content_span,
    suggestion="place the final ] at the end of the line",
  )
}

///|
fn parse_pair(
  line : @lexer.LexLine,
  equals : Int32,
  ordinal : Int32,
  options : @model.ParseOptions,
) -> Result[@model.Property, @model.Diagnostic] {
  let raw_key = line.text[0:equals].to_owned()
  let raw_value = line.text[equals + 1:].to_owned()
  let (key_start, key_finish) = trim_bounds(raw_key)
  let (value_start, value_finish) = trim_bounds(raw_value)
  let key_text = raw_key[key_start:key_finish].to_owned()
  let value_text = raw_value[value_start:value_finish].to_owned()
  if key_text.length() == 0 {
    Err(
      @model.error_diagnostic(
        "EC2003",
        "property key must not be empty",
        span=subspan(line, 0, equals),
        suggestion="add a key before the first =",
      ),
    )
  } else if key_text.char_length() > options.limits.max_key_length {
    Err(
      @model.error_diagnostic(
        "EC2004",
        "property key exceeds the configured length limit",
        span=subspan(line, key_start, key_finish),
        suggestion="shorten the key or raise max_key_length for trusted input",
      ),
    )
  } else if value_text.char_length() > options.limits.max_value_length {
    Err(
      @model.error_diagnostic(
        "EC2005",
        "property value exceeds the configured length limit",
        span=subspan(line, equals + 1 + value_start, equals + 1 + value_finish),
        suggestion="shorten the value or raise max_value_length for trusted input",
      ),
    )
  } else {
    Ok(
      @model.property(
        raw_key,
        key_text.to_lower(),
        raw_value,
        value_text,
        line.content_span,
        ordinal,
      ),
    )
  }
}

///|
/// Parse EditorConfig 0.17.2 syntax while preserving source order and raw pair
/// spellings. In recovery mode every independent line is considered. Strict
/// mode returns after the first lexical or syntax error and therefore never
/// emits a cascade of later diagnostics.
pub fn parse(
  text : String,
  source~ : String = "<memory>",
  options~ : @model.ParseOptions = @model.default_parse_options(),
) -> @model.EditorConfigDocument {
  let lexed = @lexer.lex(
    text,
    source~,
    limits=options.limits,
    accept_bom=options.accept_bom,
  )
  let preamble : Array[@model.Property] = []
  let sections : Array[@model.Section] = []
  let diagnostics : Array[@model.Diagnostic] = []
  if options.mode == @model.Strict && lexed.diagnostics.length() > 0 {
    if options.limits.max_diagnostics > 0 {
      diagnostics.push(lexed.diagnostics[0])
    }
    return @model.document(
      source,
      preamble,
      sections,
      diagnostics,
      lexed.has_bom,
      lexed.line_ending,
    )
  }
  for diagnostic in lexed.diagnostics {
    if diagnostics.length() < options.limits.max_diagnostics {
      diagnostics.push(diagnostic)
    }
  }
  if lexed.truncated {
    return @model.document(
      source,
      preamble,
      sections,
      diagnostics,
      lexed.has_bom,
      lexed.line_ending,
    )
  }
  let mut current_properties : Array[@model.Property]? = None
  let mut current_section_index : Int32? = None
  let mut seen_section = false
  let mut discard_current_section = false
  let mut property_ordinal = 0
  let mut section_ordinal = 0
  let mut property_limit_reported = false
  let mut section_limit_reported = false
  let mut halted = false
  for line in lexed.lines {
    if !halted {
      match line.kind {
        @lexer.BlankLine | @lexer.CommentLine =>
          extend_section_span(sections, current_section_index, line)
        @lexer.ContentLine =>
          if line.text[0] == 0x5B {
            seen_section = true
            current_properties = None
            current_section_index = None
            discard_current_section = false
            if line.text[line.text.length() - 1] != 0x5D {
              halted = append_diagnostic(
                diagnostics,
                options,
                unclosed_section_diagnostic(line),
              )
              discard_current_section = true
            } else {
              let raw_glob = line.text[1:line.text.length() - 1].to_owned()
              if raw_glob.char_length() > options.limits.max_glob_length {
                halted = append_diagnostic(
                  diagnostics,
                  options,
                  @model.error_diagnostic(
                    "EC2006",
                    "section glob exceeds the configured length limit",
                    span=subspan(line, 1, line.text.length() - 1),
                    suggestion="shorten the glob or raise max_glob_length for trusted input",
                  ),
                )
                discard_current_section = true
              } else if sections.length() >= options.limits.max_sections {
                if !section_limit_reported {
                  halted = append_diagnostic(
                    diagnostics,
                    options,
                    @model.error_diagnostic(
                      "EC2007",
                      "document exceeds the configured section count limit",
                      span=line.content_span,
                      suggestion="reduce the number of sections",
                    ),
                  )
                  section_limit_reported = true
                }
                discard_current_section = true
              } else {
                let properties : Array[@model.Property] = []
                let new_index = sections.length()
                sections.push(
                  @model.section(
                    raw_glob,
                    raw_glob,
                    properties,
                    line.span,
                    section_ordinal,
                  ),
                )
                current_properties = Some(properties)
                current_section_index = Some(new_index)
                section_ordinal += 1
              }
            }
          } else {
            extend_section_span(sections, current_section_index, line)
            match first_equals(line.text) {
              None =>
                halted = append_diagnostic(
                  diagnostics,
                  options,
                  invalid_line_diagnostic(line),
                )
              Some(equals) =>
                match parse_pair(line, equals, property_ordinal, options) {
                  Err(diagnostic) =>
                    halted = append_diagnostic(diagnostics, options, diagnostic)
                  Ok(property) =>
                    if property_ordinal >= options.limits.max_properties {
                      if !property_limit_reported {
                        halted = append_diagnostic(
                          diagnostics,
                          options,
                          @model.error_diagnostic(
                            "EC2008",
                            "document exceeds the configured property count limit",
                            span=line.content_span,
                            suggestion="reduce the number of properties",
                          ),
                        )
                        property_limit_reported = true
                      }
                    } else if seen_section {
                      if !discard_current_section {
                        match current_properties {
                          Some(properties) => properties.push(property)
                          None => ()
                        }
                      }
                      property_ordinal += 1
                    } else {
                      preamble.push(property)
                      property_ordinal += 1
                    }
                }
            }
          }
      }
    }
  }
  @model.document(
    source,
    preamble,
    sections,
    diagnostics,
    lexed.has_bom,
    lexed.line_ending,
  )
}

///|
/// Convenience result form for callers that do not want a partial document.
/// Recovery callers should use `parse` directly to inspect valid nodes next to
/// diagnostics.
pub fn parse_checked(
  text : String,
  source~ : String = "<memory>",
  options~ : @model.ParseOptions = @model.default_parse_options(),
) -> Result[@model.EditorConfigDocument, Array[@model.Diagnostic]] {
  let document = parse(text, source~, options~)
  if document.has_errors() {
    Err(document.diagnostics)
  } else {
    Ok(document)
  }
}

///|
pub fn parse_strict(
  text : String,
  source~ : String = "<memory>",
) -> Result[@model.EditorConfigDocument, Array[@model.Diagnostic]] {
  parse_checked(text, source~, options=@model.strict_parse_options())
}

///|
/// Parse a byte buffer only after strict UTF-8 validation. Syntax errors are
/// retained inside the successful document just like `parse`; only failure to
/// construct a valid Unicode String uses the outer Result error.
pub fn parse_utf8(
  bytes : BytesView,
  source~ : String = "<memory>",
  options~ : @model.ParseOptions = @model.default_parse_options(),
) -> Result[@model.EditorConfigDocument, @model.Diagnostic] {
  match @lexer.decode_utf8(bytes, source~) {
    Err(diagnostic) => Err(diagnostic)
    Ok(text) => Ok(parse(text, source~, options~))
  }
}
