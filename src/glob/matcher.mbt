///|
priv struct WorkBudget {
  max : Int32
  mut operations : Int32
  mut exhausted : Bool
}

///|
fn WorkBudget::step(self : WorkBudget) -> Bool {
  if self.exhausted {
    false
  } else if self.operations >= self.max {
    self.exhausted = true
    false
  } else {
    self.operations += 1
    true
  }
}

///|
fn empty_positions() -> @hashset.HashSet[Int32] {
  @hashset.HashSet([])
}

///|
fn singleton_position(value : Int32) -> @hashset.HashSet[Int32] {
  @hashset.HashSet([value])
}

///|
fn add_position(
  output : @hashset.HashSet[Int32],
  value : Int32,
  budget : WorkBudget,
) -> Unit {
  if budget.step() {
    output.add(value)
  }
}

///|
fn class_item_matches(item : ClassItem, candidate : Char) -> Bool {
  match item {
    ClassLiteral(value) => candidate == value
    ClassRange(first, last) =>
      candidate.compare(first) >= 0 && candidate.compare(last) <= 0
  }
}

///|
fn class_matches(
  class : CharacterClass,
  candidate : Char,
  budget : WorkBudget,
) -> Bool {
  let mut included = false
  for item in class.items {
    if !budget.step() {
      return false
    }
    if class_item_matches(item, candidate) {
      included = true
      break
    }
  }
  if class.negated {
    !included
  } else {
    included
  }
}

///|
fn match_literal_text(
  text : String,
  starts : @hashset.HashSet[Int32],
  input : Array[Char],
  budget : WorkBudget,
) -> @hashset.HashSet[Int32] {
  let output = empty_positions()
  let expected = text.to_array()
  for start in starts {
    if budget.exhausted {
      break
    }
    if start + expected.length() > input.length() {
      let _ = budget.step()
      continue
    }
    let mut cursor = 0
    let mut equal = true
    while cursor < expected.length() {
      if !budget.step() {
        equal = false
        break
      }
      if input[start + cursor] != expected[cursor] {
        equal = false
        break
      }
      cursor += 1
    }
    if equal {
      add_position(output, start + expected.length(), budget)
    }
  }
  output
}

///|
fn union_positions(
  output : @hashset.HashSet[Int32],
  additions : @hashset.HashSet[Int32],
  budget : WorkBudget,
) -> Unit {
  for position in additions {
    if !budget.step() {
      break
    }
    output.add(position)
  }
}

///|
fn match_choice(
  branches : Array[GlobSequence],
  starts : @hashset.HashSet[Int32],
  input : Array[Char],
  budget : WorkBudget,
) -> @hashset.HashSet[Int32] {
  let output = empty_positions()
  for branch in branches {
    if !budget.step() {
      break
    }
    let branch_positions = match_sequence(branch, starts, input, budget)
    union_positions(output, branch_positions, budget)
  }
  output
}

///|
fn match_number_range(
  range : IntegerRange,
  starts : @hashset.HashSet[Int32],
  input : Array[Char],
  budget : WorkBudget,
) -> @hashset.HashSet[Int32] {
  let output = empty_positions()
  let mut value = range.first
  while value <= range.last && !budget.exhausted {
    if !budget.step() {
      break
    }
    let matched = match_literal_text(value.to_string(), starts, input, budget)
    union_positions(output, matched, budget)
    if value == range.last {
      break
    }
    value += 1
  }
  output
}

///|
fn match_star(
  starts : @hashset.HashSet[Int32],
  input : Array[Char],
  budget : WorkBudget,
) -> @hashset.HashSet[Int32] {
  let output = empty_positions()
  for start in starts {
    add_position(output, start, budget)
    let mut cursor = start
    while cursor < input.length() && input[cursor] != '/' {
      if !budget.step() {
        break
      }
      cursor += 1
      output.add(cursor)
    }
    if budget.exhausted {
      break
    }
  }
  output
}

///|
fn match_globstar(
  starts : @hashset.HashSet[Int32],
  input : Array[Char],
  budget : WorkBudget,
) -> @hashset.HashSet[Int32] {
  let output = empty_positions()
  for start in starts {
    let mut cursor = start
    while cursor <= input.length() {
      if !budget.step() {
        break
      }
      output.add(cursor)
      cursor += 1
    }
    if budget.exhausted {
      break
    }
  }
  output
}

///|
/// A segment-position `**/` consumes either nothing, or a prefix ending at a
/// slash. Consequently `d/**/z` does not require a redundant `d//z` path.
fn match_recursive_directories(
  starts : @hashset.HashSet[Int32],
  input : Array[Char],
  budget : WorkBudget,
) -> @hashset.HashSet[Int32] {
  let output = empty_positions()
  for start in starts {
    add_position(output, start, budget)
    let mut cursor = start
    while cursor < input.length() {
      if !budget.step() {
        break
      }
      if input[cursor] == '/' {
        output.add(cursor + 1)
      }
      cursor += 1
    }
    if budget.exhausted {
      break
    }
  }
  output
}

///|
fn match_single_character(
  atom : GlobAtom,
  starts : @hashset.HashSet[Int32],
  input : Array[Char],
  budget : WorkBudget,
) -> @hashset.HashSet[Int32] {
  let output = empty_positions()
  for start in starts {
    if !budget.step() {
      break
    }
    if start >= input.length() {
      continue
    }
    let candidate = input[start]
    let accepted = match atom {
      Literal(value) => candidate == value
      Separator => candidate == '/'
      Question => candidate != '/'
      Class(class) => class_matches(class, candidate, budget)
      _ => false
    }
    if accepted {
      add_position(output, start + 1, budget)
    }
  }
  output
}

///|
fn match_atom(
  atom : GlobAtom,
  starts : @hashset.HashSet[Int32],
  input : Array[Char],
  budget : WorkBudget,
) -> @hashset.HashSet[Int32] {
  match atom {
    Star => match_star(starts, input, budget)
    GlobStar => match_globstar(starts, input, budget)
    RecursiveDirectories => match_recursive_directories(starts, input, budget)
    Choice(branches) => match_choice(branches, starts, input, budget)
    NumberRange(range) => match_number_range(range, starts, input, budget)
    Literal(_) | Separator | Question | Class(_) =>
      match_single_character(atom, starts, input, budget)
  }
}

///|
fn match_sequence(
  sequence : GlobSequence,
  starts : @hashset.HashSet[Int32],
  input : Array[Char],
  budget : WorkBudget,
) -> @hashset.HashSet[Int32] {
  let mut positions = starts.copy()
  for atom in sequence.atoms {
    if positions.is_empty() || budget.exhausted {
      break
    }
    positions = match_atom(atom, positions, input, budget)
  }
  positions
}

///|
fn initial_positions(
  anchored : Bool,
  input : Array[Char],
  budget : WorkBudget,
) -> @hashset.HashSet[Int32] {
  let output = singleton_position(0)
  if !anchored {
    let mut cursor = 0
    while cursor < input.length() {
      if !budget.step() {
        break
      }
      if input[cursor] == '/' {
        output.add(cursor + 1)
      }
      cursor += 1
    }
  }
  output
}

///|
fn match_limit_diagnostic(compiled : CompiledGlob) -> @model.Diagnostic {
  @model.error_diagnostic(
    "E_GLOB_MATCH_LIMIT",
    "glob match exceeded \{compiled.limits.max_match_operations} operations",
    span=@model.unknown_span("<glob>"),
    suggestion="simplify the glob or raise max_match_operations",
  )
}

///|
/// Execute a compiled glob with deterministic work accounting.
///
/// The matcher is an NFA-style position-set evaluator. At every AST atom it
/// deduplicates candidate offsets in a hash set, so brace alternatives do not
/// multiply path states indefinitely. Every transition and scan consumes the
/// stored operation budget.
pub fn match_glob(compiled : CompiledGlob, path : String) -> GlobMatchResult {
  if compiled.never_matches_file {
    return { matched: false, operations: 0, exhausted: false, diagnostics: [], }
  }
  let input = path.to_array()
  let budget : WorkBudget = {
    max: compiled.limits.max_match_operations,
    operations: 0,
    exhausted: false,
  }
  let starts = initial_positions(compiled.anchored, input, budget)
  let positions = match_sequence(compiled.ast, starts, input, budget)
  if budget.exhausted {
    {
      matched: false,
      operations: budget.operations,
      exhausted: true,
      diagnostics: [match_limit_diagnostic(compiled)],
    }
  } else {
    {
      matched: positions.contains(input.length()),
      operations: budget.operations,
      exhausted: false,
      diagnostics: [],
    }
  }
}

///|
/// Boolean convenience for a known-successful compile. Budget exhaustion is a
/// safe `false`; use `match_glob` when the distinction from an ordinary miss
/// matters to the caller.
pub fn glob_matches(compiled : CompiledGlob, path : String) -> Bool {
  match_glob(compiled, path).matched
}

///|
/// Compile and match in one call. Compile diagnostics are intentionally not
/// hidden by an exception; invalid/budget-rejected patterns return `false`.
pub fn matches(
  pattern : String,
  path : String,
  limits~ : @model.ResourceLimits = @model.default_limits(),
) -> Bool {
  let result = compile_glob(pattern, limits~)
  match result.glob {
    Some(compiled) => glob_matches(compiled, path)
    None => false
  }
}
