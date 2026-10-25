///|
/// One in-memory configuration file. Its path is normalized by `config_file`;
/// callers constructing this public value directly are still handled safely by
/// `memory_source` and lookup.
pub(all) struct ConfigFile {
  path : String
  text : String
} derive(Eq, @debug.Debug)

///|
pub fn config_file(path : String, text : String) -> ConfigFile {
  { path: @path.normalize(path), text, }
}

///|
/// A deterministic, mutable-by-append in-memory source. When several entries
/// compare equal under the selected case strategy, the most recently appended
/// entry wins. No host filesystem operation is performed.
pub struct MemoryConfigSource {
  files : Array[ConfigFile]
} derive(Eq, @debug.Debug)

///|
pub fn memory_source(files : Array[ConfigFile]) -> MemoryConfigSource {
  let normalized : Array[ConfigFile] = []
  for file in files {
    normalized.push(config_file(file.path, file.text))
  }
  { files: normalized, }
}

///|
pub fn empty_memory_source() -> MemoryConfigSource {
  memory_source([])
}

///|
/// Append an overlay entry. Later entries take precedence during lookup.
pub fn MemoryConfigSource::put(
  self : MemoryConfigSource,
  path : String,
  text : String,
) -> Unit {
  self.files.push(config_file(path, text))
}

///|
pub fn MemoryConfigSource::file_count(self : MemoryConfigSource) -> Int32 {
  self.files.length()
}

///|
pub fn MemoryConfigSource::paths(self : MemoryConfigSource) -> Array[String] {
  self.files.map(fn(file) { file.path })
}

///|
pub fn MemoryConfigSource::lookup(
  self : MemoryConfigSource,
  path : String,
  case : @path.CaseSensitivity,
) -> ConfigFile? {
  let wanted = @path.normalize(path)
  let mut index = self.files.length()
  while index > 0 {
    index -= 1
    let file = self.files[index]
    if @path.path_equal(file.path, wanted, case) {
      return Some(file)
    }
  }
  None
}

///|
/// Resolver behavior that must not depend on the execution host. The path
/// comparison strategy is required when constructing options; glob matching
/// remains specification-defined and case-sensitive.
pub(all) struct ResolveOptions {
  case_sensitivity : @path.CaseSensitivity
  parse_options : @model.ParseOptions
  config_name : String
} derive(Eq, @debug.Debug)

///|
pub fn resolve_options(
  case_sensitivity : @path.CaseSensitivity,
  parse_options~ : @model.ParseOptions = @model.default_parse_options(),
  config_name~ : String = ".editorconfig",
) -> ResolveOptions {
  { case_sensitivity, parse_options, config_name, }
}

///|
/// Complete deterministic output. `searched_config_paths` is nearest first,
/// mirroring upward discovery. `loaded_config_paths` is ancestor first,
/// mirroring the order in which settings were applied.
pub(all) struct ResolveResult {
  settings : @model.EffectiveSettings
  searched_config_paths : Array[String]
  loaded_config_paths : Array[String]
  stopped_by_root : String?
  case_sensitivity : @path.CaseSensitivity
} derive(Eq, @debug.Debug)

///|
pub fn ResolveResult::value(self : ResolveResult, key : String) -> String? {
  self.settings.value(key)
}

///|
pub fn ResolveResult::get(
  self : ResolveResult,
  key : String,
) -> @model.EffectiveProperty? {
  self.settings.get(key)
}

///|
pub fn ResolveResult::has_errors(self : ResolveResult) -> Bool {
  self.settings.has_errors()
}

///|
priv struct LoadedConfig {
  file : ConfigFile
  document : @model.EditorConfigDocument
}

///|
fn append_all_diagnostics(
  output : Array[@model.Diagnostic],
  input : Array[@model.Diagnostic],
) -> Unit {
  for diagnostic in input {
    output.push(diagnostic)
  }
}

///|
fn diagnostic_at(
  diagnostic : @model.Diagnostic,
  span : @model.SourceSpan,
) -> @model.Diagnostic {
  match diagnostic.suggestion {
    Some(suggestion) =>
      @model.diagnostic(
        diagnostic.severity,
        diagnostic.code,
        diagnostic.message,
        span~,
        suggestion~,
      )
    None =>
      @model.diagnostic(
        diagnostic.severity,
        diagnostic.code,
        diagnostic.message,
        span~,
      )
  }
}

///|
fn append_glob_diagnostics(
  output : Array[@model.Diagnostic],
  input : Array[@model.Diagnostic],
  span : @model.SourceSpan,
) -> Unit {
  for diagnostic in input {
    output.push(diagnostic_at(diagnostic, span))
  }
}

///|
fn resolver_path_diagnostic(
  config_path : String,
  target_path : String,
) -> @model.Diagnostic {
  @model.error_diagnostic(
    "E_RESOLVE_PATH_ROOT",
    "target path '\{target_path}' cannot be made relative to config '\{config_path}'",
    span=@model.unknown_span(config_path),
    suggestion="use paths with compatible lexical roots",
  )
}

///|
fn find_effective(
  values : Array[@model.EffectiveProperty],
  key : String,
) -> Int32? {
  for index = 0; index < values.length(); index = index + 1 {
    if values[index].key == key {
      return Some(index)
    }
  }
  None
}

///|
fn push_trace(
  trace : Array[@model.TraceEvent],
  action : @model.TraceAction,
  key : String,
  value : String,
  config_path : String,
  section_glob : String,
  span : @model.SourceSpan,
  note : String,
) -> Unit {
  trace.push(
    @model.trace_event(
      action, key, value, config_path, section_glob, span, note,
    ),
  )
}

///|
fn trace_preamble(
  loaded : LoadedConfig,
  trace : Array[@model.TraceEvent],
) -> Unit {
  for property in loaded.document.preamble {
    let note = if property.is_root() {
      "root controls upward discovery and is not an effective setting"
    } else {
      "preamble properties other than root have no effect"
    }
    push_trace(
      trace,
      @model.Ignore,
      property.key,
      property.value,
      loaded.file.path,
      "",
      property.span,
      note,
    )
  }
}

///|
fn apply_property(
  property : @model.Property,
  section : @model.Section,
  config_path : String,
  effective : Array[@model.EffectiveProperty],
  trace : Array[@model.TraceEvent],
  explain_ignored : Bool,
) -> Unit {
  if property.key == "root" {
    if explain_ignored {
      push_trace(
        trace,
        @model.Ignore,
        property.key,
        property.value,
        config_path,
        section.glob,
        property.span,
        "root is only meaningful before the first section",
      )
    }
    return
  }
  let validation = @properties.validate_property(property)
  if validation.status == @properties.Invalid {
    if explain_ignored {
      push_trace(
        trace,
        @model.Ignore,
        property.key,
        property.value,
        config_path,
        section.glob,
        property.span,
        "invalid property value was ignored",
      )
    }
    return
  }
  if validation.status == @properties.Unset {
    let note = match find_effective(effective, property.key) {
      Some(index) => {
        let previous = effective.remove(index)
        "removed value from \{previous.config_path}"
      }
      None => "no active value to remove"
    }
    push_trace(
      trace,
      @model.Unset,
      property.key,
      "unset",
      config_path,
      section.glob,
      property.span,
      note,
    )
    return
  }
  let normalized = validation.normalized_value
  let replacement = @model.effective_property(
    property.key,
    normalized,
    config_path,
    section.glob,
    property.span,
  )
  match find_effective(effective, property.key) {
    Some(index) => {
      let previous = effective[index]
      effective[index] = replacement
      push_trace(
        trace,
        @model.Override,
        property.key,
        normalized,
        config_path,
        section.glob,
        property.span,
        "overrode value from \{previous.config_path}",
      )
    }
    None => {
      effective.push(replacement)
      push_trace(
        trace,
        @model.Assign,
        property.key,
        normalized,
        config_path,
        section.glob,
        property.span,
        "assigned by matching section",
      )
    }
  }
}

///|
fn apply_section(
  loaded : LoadedConfig,
  section : @model.Section,
  relative_target : String,
  effective : Array[@model.EffectiveProperty],
  diagnostics : Array[@model.Diagnostic],
  trace : Array[@model.TraceEvent],
  limits : @model.ResourceLimits,
  explain_ignored : Bool,
) -> Unit {
  let compiled = @glob.compile_glob(section.glob, limits~)
  append_glob_diagnostics(diagnostics, compiled.diagnostics, section.span)
  guard compiled.glob is Some(glob) else {
    if explain_ignored {
      push_trace(
        trace,
        @model.Ignore,
        "",
        "",
        loaded.file.path,
        section.glob,
        section.span,
        "section glob could not be compiled",
      )
    }
    return
  }
  let matched = @glob.match_glob(glob, relative_target)
  append_glob_diagnostics(diagnostics, matched.diagnostics, section.span)
  if matched.exhausted {
    if explain_ignored {
      push_trace(
        trace,
        @model.Ignore,
        "",
        "",
        loaded.file.path,
        section.glob,
        section.span,
        "section match exhausted its operation budget",
      )
    }
  } else if !matched.matched {
    if explain_ignored {
      push_trace(
        trace,
        @model.Ignore,
        "",
        "",
        loaded.file.path,
        section.glob,
        section.span,
        "section did not match '\{relative_target}'",
      )
    }
  } else {
    for property in section.properties {
      apply_property(
        property,
        section,
        loaded.file.path,
        effective,
        trace,
        explain_ignored,
      )
    }
  }
}

///|
fn apply_loaded(
  loaded : LoadedConfig,
  target_path : String,
  options : ResolveOptions,
  effective : Array[@model.EffectiveProperty],
  diagnostics : Array[@model.Diagnostic],
  trace : Array[@model.TraceEvent],
  explain_ignored : Bool,
) -> Unit {
  append_all_diagnostics(diagnostics, loaded.document.diagnostics)
  append_all_diagnostics(
    diagnostics,
    @properties.validate_document(loaded.document),
  )
  if explain_ignored {
    trace_preamble(loaded, trace)
  }
  let config_directory = @path.dirname(loaded.file.path)
  guard @path.relative_to(
      target_path,
      config_directory,
      options.case_sensitivity,
    )
    is Some(relative_target) else {
    diagnostics.push(resolver_path_diagnostic(loaded.file.path, target_path))
    return
  }
  for section in loaded.document.sections {
    apply_section(
      loaded,
      section,
      relative_target,
      effective,
      diagnostics,
      trace,
      options.parse_options.limits,
      explain_ignored,
    )
  }
}

///|
fn resolve_internal(
  target_file : String,
  source : MemoryConfigSource,
  options : ResolveOptions,
  explain_ignored : Bool,
) -> ResolveResult {
  let target_path = @path.normalize(target_file)
  let searched_config_paths : Array[String] = []
  let nearest_first : Array[LoadedConfig] = []
  let mut stopped_by_root : String? = None
  for directory in @path.config_search_directories(target_path) {
    let candidate = @path.join(directory, options.config_name)
    searched_config_paths.push(candidate)
    match source.lookup(candidate, options.case_sensitivity) {
      Some(file) => {
        let document = @parser.parse(
          file.text,
          source=file.path,
          options=options.parse_options,
        )
        nearest_first.push({ file, document, })
        if document.stops_search() {
          stopped_by_root = Some(file.path)
          break
        }
      }
      None => ()
    }
  }
  let ancestor_first : Array[LoadedConfig] = []
  let mut index = nearest_first.length()
  while index > 0 {
    index -= 1
    ancestor_first.push(nearest_first[index])
  }
  let effective : Array[@model.EffectiveProperty] = []
  let diagnostics : Array[@model.Diagnostic] = []
  let trace : Array[@model.TraceEvent] = []
  let loaded_config_paths : Array[String] = []
  for loaded in ancestor_first {
    loaded_config_paths.push(loaded.file.path)
    apply_loaded(
      loaded, target_path, options, effective, diagnostics, trace, explain_ignored,
    )
  }
  {
    settings: { target_path, properties: effective, diagnostics, trace, },
    searched_config_paths,
    loaded_config_paths,
    stopped_by_root,
    case_sensitivity: options.case_sensitivity,
  }
}

///|
/// Resolve effective properties. Mutation events are retained in the trace;
/// ordinary non-matches and ignored pairs are omitted for a compact result.
pub fn resolve(
  target_file : String,
  source : MemoryConfigSource,
  case_sensitivity : @path.CaseSensitivity,
) -> ResolveResult {
  resolve_internal(
    target_file,
    source,
    resolve_options(case_sensitivity),
    false,
  )
}

///|
/// Resolve with custom parser/resource limits and configuration filename.
pub fn resolve_with_options(
  target_file : String,
  source : MemoryConfigSource,
  options : ResolveOptions,
) -> ResolveResult {
  resolve_internal(target_file, source, options, false)
}

///|
/// Resolve and include stable `Ignore` trace events for preamble pairs,
/// non-matching sections, invalid properties, and matcher failures.
pub fn explain(
  target_file : String,
  source : MemoryConfigSource,
  case_sensitivity : @path.CaseSensitivity,
) -> ResolveResult {
  resolve_internal(target_file, source, resolve_options(case_sensitivity), true)
}

///|
pub fn explain_with_options(
  target_file : String,
  source : MemoryConfigSource,
  options : ResolveOptions,
) -> ResolveResult {
  resolve_internal(target_file, source, options, true)
}

///|
pub extend ConfigFile with Eq::{not_equal, equal}

///|
pub extend ConfigFile with @debug.Debug::{to_repr}

///|
pub extend MemoryConfigSource with Eq::{not_equal, equal}

///|
pub extend MemoryConfigSource with @debug.Debug::{to_repr}

///|
pub extend ResolveOptions with Eq::{not_equal, equal}

///|
pub extend ResolveOptions with @debug.Debug::{to_repr}

///|
pub extend ResolveResult with Eq::{not_equal, equal}

///|
pub extend ResolveResult with @debug.Debug::{to_repr}
