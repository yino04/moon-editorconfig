///|
priv struct CompileContext {
  pattern : String
  chars : Array[Char]
  limits : @model.ResourceLimits
  diagnostics : Array[@model.Diagnostic]
  mut index : Int32
  mut alternative_count : Int32
  mut range_cardinality : Int32
  mut failed : Bool
  mut saw_separator : Bool
}

///|
fn glob_span(
  pattern : String,
  start : Int32,
  finish : Int32,
) -> @model.SourceSpan {
  @model.source_span(
    pattern,
    @model.source_pos(start, 1, start + 1),
    @model.source_pos(finish, 1, finish + 1),
  )
}

///|
fn CompileContext::error(
  self : CompileContext,
  code : String,
  message : String,
  start : Int32,
  finish : Int32,
  suggestion? : String,
) -> Unit {
  self.failed = true
  if self.diagnostics.length() < self.limits.max_diagnostics {
    self.diagnostics.push(
      @model.error_diagnostic(
        code,
        message,
        span=glob_span(self.pattern, start, finish),
        suggestion?,
      ),
    )
  }
}

///|
fn is_escaped(chars : Array[Char], target : Int32, lower_bound : Int32) -> Bool {
  let mut backslashes = 0
  let mut cursor = target - 1
  while cursor >= lower_bound && chars[cursor] == '\\' {
    backslashes += 1
    cursor -= 1
  }
  backslashes % 2 == 1
}

///|
/// Find a brace paired with `open`. Braces and commas inside classes are
/// literal; escaped characters do not participate in balancing.
fn find_closing_brace(
  ctx : CompileContext,
  open : Int32,
  end : Int32,
) -> Int32? {
  let mut cursor = open + 1
  let mut depth = 1
  let mut in_class = false
  while cursor < end {
    let current = ctx.chars[cursor]
    if current == '\\' {
      cursor += 2
      continue
    }
    if in_class {
      if current == ']' {
        in_class = false
      }
      cursor += 1
      continue
    }
    if current == '[' {
      in_class = true
    } else if current == '{' {
      depth += 1
    } else if current == '}' {
      depth -= 1
      if depth == 0 {
        return Some(cursor)
      }
    }
    cursor += 1
  }
  None
}

///|
fn has_top_level_comma(
  ctx : CompileContext,
  start : Int32,
  finish : Int32,
) -> Bool {
  let mut cursor = start
  let mut depth = 0
  let mut in_class = false
  while cursor < finish {
    let current = ctx.chars[cursor]
    if current == '\\' {
      cursor += 2
      continue
    }
    if in_class {
      if current == ']' {
        in_class = false
      }
      cursor += 1
      continue
    }
    match current {
      '[' => in_class = true
      '{' => depth += 1
      '}' => if depth > 0 { depth -= 1 }
      ',' => if depth == 0 { return true }
      _ => ()
    }
    cursor += 1
  }
  false
}

///|
fn chars_to_string(
  chars : Array[Char],
  start : Int32,
  finish : Int32,
) -> String {
  let output : Array[Char] = []
  let mut cursor = start
  while cursor < finish {
    output.push(chars[cursor])
    cursor += 1
  }
  String::from_array(output)
}

///|
fn valid_signed_decimal(text : String) -> Bool {
  let chars = text.to_array()
  if chars.length() == 0 {
    return false
  }
  let mut cursor = if chars[0] == '-' || chars[0] == '+' { 1 } else { 0 }
  if cursor == chars.length() {
    return false
  }
  while cursor < chars.length() {
    if !chars[cursor].is_ascii_digit() {
      return false
    }
    cursor += 1
  }
  true
}

///|
fn parse_int_option(text : String) -> Int32? {
  try @string.parse_int(text) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
/// Return the sole top-level `..` separator when the whole brace body has the
/// numeric-range lexical form. Nested syntax and escaped dots are excluded.
fn numeric_separator(
  ctx : CompileContext,
  start : Int32,
  finish : Int32,
) -> Int32? {
  let mut found : Int32? = None
  let mut cursor = start
  while cursor + 1 < finish {
    if ctx.chars[cursor] == '.' &&
      ctx.chars[cursor + 1] == '.' &&
      !is_escaped(ctx.chars, cursor, start) {
      if found is Some(_) {
        return None
      }
      found = Some(cursor)
      cursor += 2
    } else {
      cursor += 1
    }
  }
  found
}

///|
/// The subtraction is arranged to avoid wrapping when an adversarial range
/// crosses the full signed integer domain.
fn range_cardinality_with_limit(
  first : Int32,
  last : Int32,
  limit : Int32,
) -> Int32? {
  if first >= last || limit <= 0 {
    return None
  }
  if first < 0 && last >= 0 {
    if first < -limit || last >= limit {
      return None
    }
  }
  let distance = last - first
  if distance < 0 || distance >= limit {
    None
  } else {
    Some(distance + 1)
  }
}

///|
/// Distinguish "not numeric syntax" from "numeric but rejected by bounds".
priv enum NumericBrace {
  NotNumeric
  DescendingOrEqual
  TooLarge
  Numeric(IntegerRange)
}

///|
fn parse_numeric_brace(
  ctx : CompileContext,
  start : Int32,
  finish : Int32,
) -> NumericBrace {
  guard numeric_separator(ctx, start, finish) is Some(separator) else {
    return NotNumeric
  }
  let first_text = chars_to_string(ctx.chars, start, separator)
  let last_text = chars_to_string(ctx.chars, separator + 2, finish)
  if !valid_signed_decimal(first_text) || !valid_signed_decimal(last_text) {
    return NotNumeric
  }
  guard parse_int_option(first_text) is Some(first) else { return TooLarge }
  guard parse_int_option(last_text) is Some(last) else { return TooLarge }
  if first >= last {
    return DescendingOrEqual
  }
  match
    range_cardinality_with_limit(first, last, ctx.limits.max_range_cardinality) {
    Some(cardinality) => Numeric({ first, last, cardinality, })
    None => TooLarge
  }
}

///|
fn literal_atoms(
  chars : Array[Char],
  start : Int32,
  finish : Int32,
) -> Array[GlobAtom] {
  let result : Array[GlobAtom] = []
  let mut cursor = start
  while cursor < finish {
    result.push(Literal(chars[cursor]))
    cursor += 1
  }
  result
}

///|
fn find_class_close(ctx : CompileContext, open : Int32, end : Int32) -> Int32? {
  let mut cursor = open + 1
  while cursor < end {
    if ctx.chars[cursor] == '\\' && cursor + 1 < end {
      cursor += 2
    } else if ctx.chars[cursor] == ']' {
      return Some(cursor)
    } else {
      cursor += 1
    }
  }
  None
}

///|
/// Determine anchoring from a raw slice. A slash in a successfully closed
/// class is a class member, while a slash after an unmatched `[` is an ordinary
/// separator because the opener itself is compiled literally.
fn slice_has_separator(
  ctx : CompileContext,
  start : Int32,
  finish : Int32,
) -> Bool {
  let mut cursor = start
  while cursor < finish {
    if ctx.chars[cursor] == '\\' && cursor + 1 < finish {
      cursor += 2
    } else if ctx.chars[cursor] == '[' {
      match find_class_close(ctx, cursor, finish) {
        Some(close) => cursor = close + 1
        None => cursor += 1
      }
    } else if ctx.chars[cursor] == '/' {
      return true
    } else {
      cursor += 1
    }
  }
  false
}

///|
/// Decode class contents while remembering which characters were escaped.
fn decode_class_content(
  ctx : CompileContext,
  start : Int32,
  finish : Int32,
) -> (Array[Char], Array[Bool]) {
  let values : Array[Char] = []
  let escaped : Array[Bool] = []
  let mut cursor = start
  while cursor < finish {
    if ctx.chars[cursor] == '\\' && cursor + 1 < finish {
      values.push(ctx.chars[cursor + 1])
      escaped.push(true)
      cursor += 2
    } else {
      values.push(ctx.chars[cursor])
      escaped.push(false)
      cursor += 1
    }
  }
  (values, escaped)
}

///|
fn compile_class(
  ctx : CompileContext,
  open : Int32,
  close : Int32,
) -> CharacterClass? {
  let (values, escaped) = decode_class_content(ctx, open + 1, close)
  if values.length() == 0 {
    return None
  }
  let negated = values[0] == '!' && !escaped[0]
  let mut cursor = if negated { 1 } else { 0 }
  if cursor == values.length() {
    return None
  }
  let items : Array[ClassItem] = []
  while cursor < values.length() {
    if cursor + 2 < values.length() &&
      values[cursor + 1] == '-' &&
      !escaped[cursor + 1] {
      let first = values[cursor]
      let last = values[cursor + 2]
      if first.compare(last) <= 0 {
        items.push(ClassRange(first, last))
        cursor += 3
        continue
      }
    }
    items.push(ClassLiteral(values[cursor]))
    cursor += 1
  }
  Some({ negated, items, })
}

///|
fn previous_is_segment_boundary(atoms : Array[GlobAtom]) -> Bool {
  atoms.length() == 0 || atoms[atoms.length() - 1] is Separator
}

///|
fn parse_star_run(
  ctx : CompileContext,
  end : Int32,
  atoms : Array[GlobAtom],
) -> Unit {
  let start = ctx.index
  while ctx.index < end && ctx.chars[ctx.index] == '*' {
    ctx.index += 1
  }
  let width = ctx.index - start
  if width == 1 {
    atoms.push(Star)
    return
  }
  if ctx.index < end &&
    ctx.chars[ctx.index] == '/' &&
    previous_is_segment_boundary(atoms) {
    atoms.push(RecursiveDirectories)
    ctx.saw_separator = true
    ctx.index += 1
  } else {
    atoms.push(GlobStar)
  }
}

///|
fn parse_choice(
  ctx : CompileContext,
  open : Int32,
  close : Int32,
  depth : Int32,
) -> Array[GlobAtom] {
  if depth >= ctx.limits.max_glob_nesting {
    ctx.error(
      "E_GLOB_NESTING_LIMIT",
      "glob brace nesting exceeds the configured limit",
      open,
      close + 1,
      suggestion="reduce nested brace expressions or raise max_glob_nesting",
    )
    ctx.index = close + 1
    return []
  }
  ctx.index = open + 1
  let branches : Array[GlobSequence] = []
  while ctx.index <= close {
    let branch = parse_sequence(ctx, close, true, depth + 1)
    branches.push(branch)
    if ctx.index < close && ctx.chars[ctx.index] == ',' {
      ctx.index += 1
    } else {
      break
    }
  }
  ctx.index = close + 1
  ctx.alternative_count += branches.length()
  if ctx.alternative_count > ctx.limits.max_alternatives {
    ctx.error(
      "E_GLOB_ALTERNATIVE_LIMIT",
      "glob alternatives exceed the configured limit",
      open,
      close + 1,
      suggestion="reduce brace alternatives or raise max_alternatives",
    )
    []
  } else {
    [Choice(branches)]
  }
}

///|
fn parse_brace(
  ctx : CompileContext,
  end : Int32,
  depth : Int32,
) -> Array[GlobAtom] {
  let open = ctx.index
  guard find_closing_brace(ctx, open, end) is Some(close) else {
    ctx.index += 1
    return [Literal('{')]
  }
  if has_top_level_comma(ctx, open + 1, close) {
    return parse_choice(ctx, open, close, depth)
  }
  match parse_numeric_brace(ctx, open + 1, close) {
    Numeric(range) => {
      if depth >= ctx.limits.max_glob_nesting {
        ctx.error(
          "E_GLOB_NESTING_LIMIT",
          "glob brace nesting exceeds the configured limit",
          open,
          close + 1,
          suggestion="reduce nested brace expressions or raise max_glob_nesting",
        )
        ctx.index = close + 1
        return []
      }
      ctx.range_cardinality += range.cardinality
      if ctx.range_cardinality > ctx.limits.max_range_cardinality {
        ctx.error(
          "E_GLOB_RANGE_LIMIT",
          "combined numeric ranges exceed the configured cardinality limit",
          open,
          close + 1,
          suggestion="use smaller numeric ranges or raise max_range_cardinality",
        )
        ctx.index = close + 1
        []
      } else {
        ctx.index = close + 1
        [NumberRange(range)]
      }
    }
    TooLarge => {
      ctx.error(
        "E_GLOB_RANGE_LIMIT",
        "numeric range exceeds the configured cardinality or integer limit",
        open,
        close + 1,
        suggestion="use a smaller ascending integer range",
      )
      ctx.index = close + 1
      []
    }
    // The specification only recognizes strictly ascending numeric ranges.
    // All other single-body braces retain their literal spelling.
    NotNumeric | DescendingOrEqual => {
      if slice_has_separator(ctx, open, close + 1) {
        ctx.saw_separator = true
      }
      ctx.index = close + 1
      literal_atoms(ctx.chars, open, close + 1)
    }
  }
}

///|
fn parse_sequence(
  ctx : CompileContext,
  end : Int32,
  stop_at_comma : Bool,
  depth : Int32,
) -> GlobSequence {
  let atoms : Array[GlobAtom] = []
  while ctx.index < end {
    let current = ctx.chars[ctx.index]
    if stop_at_comma && current == ',' {
      break
    }
    match current {
      '\\' =>
        if ctx.index + 1 < end {
          atoms.push(Literal(ctx.chars[ctx.index + 1]))
          ctx.index += 2
        } else {
          atoms.push(Literal('\\'))
          ctx.index += 1
        }
      '/' => {
        atoms.push(Separator)
        ctx.saw_separator = true
        ctx.index += 1
      }
      '*' => parse_star_run(ctx, end, atoms)
      '?' => {
        atoms.push(Question)
        ctx.index += 1
      }
      '[' =>
        match find_class_close(ctx, ctx.index, end) {
          Some(close) =>
            match compile_class(ctx, ctx.index, close) {
              Some(class) => {
                atoms.push(Class(class))
                ctx.index = close + 1
              }
              None => {
                atoms.push(Literal('['))
                ctx.index += 1
              }
            }
          None => {
            atoms.push(Literal('['))
            ctx.index += 1
          }
        }
      '{' => {
        let compiled = parse_brace(ctx, end, depth)
        for atom in compiled {
          atoms.push(atom)
        }
      }
      _ => {
        atoms.push(Literal(current))
        ctx.index += 1
      }
    }
  }
  { atoms, }
}

///|
fn last_raw_character_is_separator(pattern : String) -> Bool {
  let chars = pattern.to_array()
  if chars.length() == 0 || chars[chars.length() - 1] != '/' {
    return false
  }
  !is_escaped(chars, chars.length() - 1, 0)
}

///|
fn relevant_limits_are_positive(limits : @model.ResourceLimits) -> Bool {
  limits.max_glob_length > 0 &&
  limits.max_diagnostics > 0 &&
  limits.max_glob_nesting > 0 &&
  limits.max_alternatives > 0 &&
  limits.max_range_cardinality > 0 &&
  limits.max_match_operations > 0
}

///|
/// Compile an EditorConfig 0.17.2 glob to an explicit bounded AST.
///
/// Malformed singleton/unclosed brace and bracket constructs are literal, as
/// required by the reference core tests. Only resource and configured-size
/// failures prevent creation of `CompiledGlob`.
pub fn compile_glob(
  pattern : String,
  limits~ : @model.ResourceLimits = @model.default_limits(),
) -> GlobCompileResult {
  let diagnostics : Array[@model.Diagnostic] = []
  if !relevant_limits_are_positive(limits) {
    diagnostics.push(
      @model.error_diagnostic(
        "E_GLOB_LIMITS",
        "glob limits must all be positive",
        span=@model.unknown_span("<glob>"),
        suggestion="start from model.default_limits() and override one field",
      ),
    )
    return { glob: None, diagnostics, }
  }
  if pattern.length() > limits.max_glob_length {
    diagnostics.push(
      @model.error_diagnostic(
        "E_GLOB_LENGTH",
        "glob length \{pattern.length()} exceeds limit \{limits.max_glob_length}",
        span=glob_span(pattern, 0, pattern.length()),
        suggestion="shorten the section glob or raise max_glob_length",
      ),
    )
    return { glob: None, diagnostics, }
  }
  let chars = pattern.to_array()
  let leading_separator = chars.length() > 0 && chars[0] == '/'
  let ctx : CompileContext = {
    pattern,
    chars,
    limits,
    diagnostics,
    index: if leading_separator {
      1
    } else {
      0
    },
    alternative_count: 0,
    range_cardinality: 0,
    failed: false,
    saw_separator: leading_separator,
  }
  let ast = parse_sequence(ctx, chars.length(), false, 0)
  if ctx.failed {
    { glob: None, diagnostics, }
  } else {
    let compiled : CompiledGlob = {
      pattern,
      ast,
      anchored: ctx.saw_separator,
      never_matches_file: last_raw_character_is_separator(pattern),
      alternative_count: ctx.alternative_count,
      range_cardinality: ctx.range_cardinality,
      limits,
    }
    { glob: Some(compiled), diagnostics, }
  }
}
