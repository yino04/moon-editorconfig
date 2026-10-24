///|
/// Severity attached to a parser, validator, resolver, or I/O diagnostic.
pub(all) enum Severity {
  Info
  Warning
  Error
} derive(Eq, @debug.Debug)

///|
pub fn Severity::label(self : Severity) -> String {
  match self {
    Info => "info"
    Warning => "warning"
    Error => "error"
  }
}

///|
pub fn all_severities() -> Array[Severity] {
  [Info, Warning, Error]
}

///|
/// Parser behavior when invalid input is encountered.
pub(all) enum ParseMode {
  Recover
  Strict
} derive(Eq, @debug.Debug)

///|
/// The normative EditorConfig specification selected by this release.
pub(all) enum SpecVersion {
  V0_17_2
} derive(Eq, @debug.Debug)

///|
pub fn SpecVersion::to_string(self : SpecVersion) -> String {
  match self {
    V0_17_2 => "0.17.2"
  }
}

///|
/// Line-ending styles observed by the lexer.
pub(all) enum LineEnding {
  None
  Lf
  CrLf
  Mixed
} derive(Eq, @debug.Debug)

///|
pub fn LineEnding::label(self : LineEnding) -> String {
  match self {
    None => "none"
    Lf => "lf"
    CrLf => "crlf"
    Mixed => "mixed"
  }
}

///|
pub fn all_line_endings() -> Array[LineEnding] {
  [None, Lf, CrLf, Mixed]
}

///|
/// A zero-based byte/code-unit offset paired with one-based human coordinates.
pub(all) struct SourcePos {
  offset : Int32
  line : Int32
  column : Int32
} derive(Eq, @debug.Debug)

///|
pub fn source_origin() -> SourcePos {
  { offset: 0, line: 1, column: 1, }
}

///|
pub fn source_pos(offset : Int32, line : Int32, column : Int32) -> SourcePos {
  { offset, line, column, }
}

///|
pub fn SourcePos::next_column(
  self : SourcePos,
  width~ : Int32 = 1,
) -> SourcePos {
  let safe_width = if width < 0 { 0 } else { width }
  {
    offset: self.offset + safe_width,
    line: self.line,
    column: self.column + safe_width,
  }
}

///|
pub fn SourcePos::next_line(self : SourcePos, width~ : Int32 = 1) -> SourcePos {
  let safe_width = if width < 0 { 0 } else { width }
  { offset: self.offset + safe_width, line: self.line + 1, column: 1, }
}

///|
/// A half-open source interval `[start, end)`.
pub(all) struct SourceSpan {
  source : String
  start : SourcePos
  end : SourcePos
} derive(Eq, @debug.Debug)

///|
pub fn source_span(
  source : String,
  start : SourcePos,
  end : SourcePos,
) -> SourceSpan {
  { source, start, end, }
}

///|
pub fn unknown_span(source : String) -> SourceSpan {
  let origin = source_origin()
  { source, start: origin, end: origin, }
}

///|
pub fn SourceSpan::is_empty(self : SourceSpan) -> Bool {
  self.start.offset == self.end.offset
}

///|
pub fn SourceSpan::contains_offset(self : SourceSpan, offset : Int32) -> Bool {
  offset >= self.start.offset && offset < self.end.offset
}

///|
pub fn SourceSpan::merge(self : SourceSpan, other : SourceSpan) -> SourceSpan {
  if self.source != other.source {
    self
  } else {
    let start = if self.start.offset <= other.start.offset {
      self.start
    } else {
      other.start
    }
    let end = if self.end.offset >= other.end.offset {
      self.end
    } else {
      other.end
    }
    { source: self.source, start, end, }
  }
}

///|
/// Stable machine-readable diagnostic codes.
pub(all) struct Diagnostic {
  severity : Severity
  code : String
  message : String
  suggestion : String?
  span : SourceSpan?
} derive(Eq, @debug.Debug)

///|
pub fn diagnostic(
  severity : Severity,
  code : String,
  message : String,
  span? : SourceSpan,
  suggestion? : String,
) -> Diagnostic {
  { severity, code, message, suggestion, span, }
}

///|
pub fn error_diagnostic(
  code : String,
  message : String,
  span? : SourceSpan,
  suggestion? : String,
) -> Diagnostic {
  diagnostic(Error, code, message, span?, suggestion?)
}

///|
pub fn warning_diagnostic(
  code : String,
  message : String,
  span? : SourceSpan,
  suggestion? : String,
) -> Diagnostic {
  diagnostic(Warning, code, message, span?, suggestion?)
}

///|
pub fn Diagnostic::is_error(self : Diagnostic) -> Bool {
  self.severity == Error
}

///|
pub fn Diagnostic::location_label(self : Diagnostic) -> String {
  match self.span {
    None => "<unknown>"
    Some(span) => "\{span.source}:\{span.start.line}:\{span.start.column}"
  }
}

///|
/// A parsed pair. Raw spelling and normalized spelling are both retained.
pub(all) struct Property {
  raw_key : String
  key : String
  raw_value : String
  value : String
  span : SourceSpan
  ordinal : Int32
} derive(Eq, @debug.Debug)

///|
pub fn property(
  raw_key : String,
  key : String,
  raw_value : String,
  value : String,
  span : SourceSpan,
  ordinal : Int32,
) -> Property {
  { raw_key, key, raw_value, value, span, ordinal, }
}

///|
pub fn Property::is_unset(self : Property) -> Bool {
  self.value.equal_ignore_ascii_case("unset")
}

///|
pub fn Property::is_root(self : Property) -> Bool {
  self.key == "root"
}

///|
/// A section preserves pair order and the original glob spelling.
pub(all) struct Section {
  raw_glob : String
  glob : String
  properties : Array[Property]
  span : SourceSpan
  ordinal : Int32
} derive(Eq, @debug.Debug)

///|
pub fn section(
  raw_glob : String,
  glob : String,
  properties : Array[Property],
  span : SourceSpan,
  ordinal : Int32,
) -> Section {
  { raw_glob, glob, properties, span, ordinal, }
}

///|
pub fn Section::last_property(self : Section, key : String) -> Property? {
  let normalized = key.to_lower()
  let mut found : Property? = None
  for prop in self.properties {
    if prop.key == normalized {
      found = Some(prop)
    }
  }
  found
}

///|
pub fn Section::has_property(self : Section, key : String) -> Bool {
  self.last_property(key) is Some(_)
}

///|
/// Complete ordered parse output, including recoverable diagnostics.
pub(all) struct EditorConfigDocument {
  source : String
  preamble : Array[Property]
  sections : Array[Section]
  diagnostics : Array[Diagnostic]
  has_bom : Bool
  line_ending : LineEnding
} derive(Eq, @debug.Debug)

///|
pub fn document(
  source : String,
  preamble : Array[Property],
  sections : Array[Section],
  diagnostics : Array[Diagnostic],
  has_bom : Bool,
  line_ending : LineEnding,
) -> EditorConfigDocument {
  { source, preamble, sections, diagnostics, has_bom, line_ending, }
}

///|
pub fn empty_document(source : String) -> EditorConfigDocument {
  {
    source,
    preamble: [],
    sections: [],
    diagnostics: [],
    has_bom: false,
    line_ending: None,
  }
}

///|
pub fn EditorConfigDocument::has_errors(self : EditorConfigDocument) -> Bool {
  self.diagnostics.any(fn(diag) { diag.is_error() })
}

///|
pub fn EditorConfigDocument::error_count(self : EditorConfigDocument) -> Int32 {
  self.diagnostics.count_if(fn(diag) { diag.is_error() })
}

///|
pub fn EditorConfigDocument::warning_count(
  self : EditorConfigDocument,
) -> Int32 {
  self.diagnostics.count_if(fn(diag) { diag.severity == Warning })
}

///|
pub fn EditorConfigDocument::root_value(self : EditorConfigDocument) -> String? {
  let mut found : String? = None
  for prop in self.preamble {
    if prop.is_root() {
      found = Some(prop.value)
    }
  }
  found
}

///|
pub fn EditorConfigDocument::stops_search(self : EditorConfigDocument) -> Bool {
  match self.root_value() {
    Some(value) => value.equal_ignore_ascii_case("true")
    None => false
  }
}

///|
pub fn EditorConfigDocument::property_count(
  self : EditorConfigDocument,
) -> Int32 {
  self.sections.fold(init=self.preamble.length(), fn(total, item) {
    total + item.properties.length()
  })
}

///|
/// Bounded-work controls shared by parsing and glob compilation.
pub(all) struct ResourceLimits {
  max_key_length : Int32
  max_value_length : Int32
  max_glob_length : Int32
  max_document_length : Int32
  max_sections : Int32
  max_properties : Int32
  max_diagnostics : Int32
  max_glob_nesting : Int32
  max_alternatives : Int32
  max_range_cardinality : Int32
  max_match_operations : Int32
} derive(Eq, @debug.Debug)

///|
pub fn default_limits() -> ResourceLimits {
  {
    max_key_length: 4096,
    max_value_length: 16384,
    max_glob_length: 4096,
    max_document_length: 8 * 1024 * 1024,
    max_sections: 16384,
    max_properties: 262144,
    max_diagnostics: 1024,
    max_glob_nesting: 32,
    max_alternatives: 4096,
    max_range_cardinality: 10000,
    max_match_operations: 1000000,
  }
}

///|
pub fn ResourceLimits::is_valid(self : ResourceLimits) -> Bool {
  self.max_key_length >= 1024 &&
  self.max_value_length >= 4096 &&
  self.max_glob_length >= 1024 &&
  self.max_document_length > 0 &&
  self.max_sections > 0 &&
  self.max_properties > 0 &&
  self.max_diagnostics > 0 &&
  self.max_glob_nesting > 0 &&
  self.max_alternatives > 0 &&
  self.max_range_cardinality > 0 &&
  self.max_match_operations > 0
}

///|
pub(all) struct ParseOptions {
  mode : ParseMode
  spec : SpecVersion
  limits : ResourceLimits
  accept_bom : Bool
} derive(Eq, @debug.Debug)

///|
pub fn default_parse_options() -> ParseOptions {
  { mode: Recover, spec: V0_17_2, limits: default_limits(), accept_bom: true, }
}

///|
pub fn strict_parse_options() -> ParseOptions {
  let options = default_parse_options()
  { ..options, mode: Strict, }
}

///|
pub(all) enum TraceAction {
  Assign
  Override
  Unset
  Ignore
} derive(Eq, @debug.Debug)

///|
pub fn TraceAction::label(self : TraceAction) -> String {
  match self {
    Assign => "assign"
    Override => "override"
    Unset => "unset"
    Ignore => "ignore"
  }
}

///|
pub fn all_trace_actions() -> Array[TraceAction] {
  [Assign, Override, Unset, Ignore]
}

///|
pub(all) struct TraceEvent {
  action : TraceAction
  key : String
  value : String
  config_path : String
  section_glob : String
  span : SourceSpan
  note : String
} derive(Eq, @debug.Debug)

///|
pub fn trace_event(
  action : TraceAction,
  key : String,
  value : String,
  config_path : String,
  section_glob : String,
  span : SourceSpan,
  note : String,
) -> TraceEvent {
  { action, key, value, config_path, section_glob, span, note, }
}

///|
pub(all) struct EffectiveProperty {
  key : String
  value : String
  config_path : String
  section_glob : String
  span : SourceSpan
} derive(Eq, @debug.Debug)

///|
pub fn effective_property(
  key : String,
  value : String,
  config_path : String,
  section_glob : String,
  span : SourceSpan,
) -> EffectiveProperty {
  { key, value, config_path, section_glob, span, }
}

///|
pub(all) struct EffectiveSettings {
  target_path : String
  properties : Array[EffectiveProperty]
  diagnostics : Array[Diagnostic]
  trace : Array[TraceEvent]
} derive(Eq, @debug.Debug)

///|
pub fn empty_settings(target_path : String) -> EffectiveSettings {
  { target_path, properties: [], diagnostics: [], trace: [], }
}

///|
pub fn EffectiveSettings::get(
  self : EffectiveSettings,
  key : String,
) -> EffectiveProperty? {
  let normalized = key.to_lower()
  let mut found : EffectiveProperty? = None
  for prop in self.properties {
    if prop.key == normalized {
      found = Some(prop)
    }
  }
  found
}

///|
pub fn EffectiveSettings::value(
  self : EffectiveSettings,
  key : String,
) -> String? {
  match self.get(key) {
    Some(prop) => Some(prop.value)
    None => None
  }
}

///|
pub fn EffectiveSettings::has_errors(self : EffectiveSettings) -> Bool {
  self.diagnostics.any(fn(diag) { diag.is_error() })
}

///|
pub extend Severity with Eq::{not_equal, equal}

///|
pub extend Severity with @debug.Debug::{to_repr}

///|
pub extend ParseMode with Eq::{not_equal, equal}

///|
pub extend ParseMode with @debug.Debug::{to_repr}

///|
pub extend SpecVersion with Eq::{not_equal, equal}

///|
pub extend SpecVersion with @debug.Debug::{to_repr}

///|
pub extend LineEnding with Eq::{not_equal, equal}

///|
pub extend LineEnding with @debug.Debug::{to_repr}

///|
pub extend SourcePos with Eq::{not_equal, equal}

///|
pub extend SourcePos with @debug.Debug::{to_repr}

///|
pub extend SourceSpan with Eq::{not_equal, equal}

///|
pub extend SourceSpan with @debug.Debug::{to_repr}

///|
pub extend Diagnostic with Eq::{not_equal, equal}

///|
pub extend Diagnostic with @debug.Debug::{to_repr}

///|
pub extend Property with Eq::{not_equal, equal}

///|
pub extend Property with @debug.Debug::{to_repr}

///|
pub extend Section with Eq::{not_equal, equal}

///|
pub extend Section with @debug.Debug::{to_repr}

///|
pub extend EditorConfigDocument with Eq::{not_equal, equal}

///|
pub extend EditorConfigDocument with @debug.Debug::{to_repr}

///|
pub extend ResourceLimits with Eq::{not_equal, equal}

///|
pub extend ResourceLimits with @debug.Debug::{to_repr}

///|
pub extend ParseOptions with Eq::{not_equal, equal}

///|
pub extend ParseOptions with @debug.Debug::{to_repr}

///|
pub extend TraceAction with Eq::{not_equal, equal}

///|
pub extend TraceAction with @debug.Debug::{to_repr}

///|
pub extend TraceEvent with Eq::{not_equal, equal}

///|
pub extend TraceEvent with @debug.Debug::{to_repr}

///|
pub extend EffectiveProperty with Eq::{not_equal, equal}

///|
pub extend EffectiveProperty with @debug.Debug::{to_repr}

///|
pub extend EffectiveSettings with Eq::{not_equal, equal}

///|
pub extend EffectiveSettings with @debug.Debug::{to_repr}
