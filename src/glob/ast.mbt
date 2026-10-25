///|
/// One member of an EditorConfig bracket expression.
///
/// A range is inclusive. A dash that is first or last in a class is compiled
/// as `ClassLiteral('-')`, not as a range endpoint.
pub(all) enum ClassItem {
  ClassLiteral(Char)
  ClassRange(Char, Char)
} derive(Eq, @debug.Debug)

///|
pub extend ClassItem with Eq::{not_equal, equal}

///|
pub extend ClassItem with @debug.Debug::{to_repr}

///|
/// Explicit representation of `[seq]` and `[!seq]`.
pub(all) struct CharacterClass {
  negated : Bool
  items : Array[ClassItem]
} derive(Eq, @debug.Debug)

///|
pub extend CharacterClass with Eq::{not_equal, equal}

///|
pub extend CharacterClass with @debug.Debug::{to_repr}

///|
/// A specification numeric range. Values are stored as numbers instead of an
/// eagerly expanded array, keeping compilation memory bounded by pattern size.
pub(all) struct IntegerRange {
  first : Int32
  last : Int32
  cardinality : Int32
} derive(Eq, @debug.Debug)

///|
pub extend IntegerRange with Eq::{not_equal, equal}

///|
pub extend IntegerRange with @debug.Debug::{to_repr}

///|
/// A sequence is the concatenation unit of the glob AST. `Choice` branches
/// contain more sequences, so nested braces remain explicit and inspectable.
pub(all) struct GlobSequence {
  atoms : Array[GlobAtom]
} derive(Eq, @debug.Debug)

///|
/// Compiled atoms. No regular expression is created or evaluated.
///
/// `RecursiveDirectories` represents a segment-position `**/`. Unlike a
/// generic `GlobStar`, it may consume zero complete directory segments. This
/// is what makes `d/**/z` match both `d/z` and `d/a/b/z`.
pub(all) enum GlobAtom {
  Literal(Char)
  Separator
  Star
  GlobStar
  RecursiveDirectories
  Question
  Class(CharacterClass)
  Choice(Array[GlobSequence])
  NumberRange(IntegerRange)
} derive(Eq, @debug.Debug)

///|
pub extend GlobSequence with Eq::{not_equal, equal}

///|
pub extend GlobSequence with @debug.Debug::{to_repr}

///|
pub extend GlobAtom with Eq::{not_equal, equal}

///|
pub extend GlobAtom with @debug.Debug::{to_repr}

///|
/// Immutable product of successful compilation.
pub(all) struct CompiledGlob {
  pattern : String
  ast : GlobSequence
  anchored : Bool
  never_matches_file : Bool
  alternative_count : Int32
  range_cardinality : Int32
  limits : @model.ResourceLimits
} derive(Eq, @debug.Debug)

///|
pub extend CompiledGlob with Eq::{not_equal, equal}

///|
pub extend CompiledGlob with @debug.Debug::{to_repr}

///|
/// Compilation keeps diagnostics separate from the optional executable AST.
/// Resource-limit failures never leave a partially usable matcher behind.
pub(all) struct GlobCompileResult {
  glob : CompiledGlob?
  diagnostics : Array[@model.Diagnostic]
} derive(Eq, @debug.Debug)

///|
pub extend GlobCompileResult with Eq::{not_equal, equal}

///|
pub extend GlobCompileResult with @debug.Debug::{to_repr}

///|
pub fn GlobCompileResult::is_ok(self : GlobCompileResult) -> Bool {
  self.glob is Some(_) && self.diagnostics.all(fn(item) { !item.is_error() })
}

///|
/// Detailed match output. `glob_matches` is the small Boolean convenience API;
/// callers that need to distinguish an ordinary miss from exhausted work use
/// this structure through `match_glob`.
pub(all) struct GlobMatchResult {
  matched : Bool
  operations : Int32
  exhausted : Bool
  diagnostics : Array[@model.Diagnostic]
} derive(Eq, @debug.Debug)

///|
pub extend GlobMatchResult with Eq::{not_equal, equal}

///|
pub extend GlobMatchResult with @debug.Debug::{to_repr}

///|
pub fn GlobMatchResult::completed(self : GlobMatchResult) -> Bool {
  !self.exhausted
}
