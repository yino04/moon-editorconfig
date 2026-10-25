///|
/// Parse EditorConfig text in recoverable mode while preserving source order,
/// raw spellings, spans, and diagnostics.
pub fn parse(
  text : String,
  source~ : String = "<memory>",
  options~ : @model.ParseOptions = @model.default_parse_options(),
) -> @model.EditorConfigDocument {
  @parser.parse(text, source~, options~)
}

///|
/// Parse and return `Err` when any error diagnostic was produced.
pub fn parse_checked(
  text : String,
  source~ : String = "<memory>",
  options~ : @model.ParseOptions = @model.default_parse_options(),
) -> Result[@model.EditorConfigDocument, Array[@model.Diagnostic]] {
  @parser.parse_checked(text, source~, options~)
}

///|
pub fn compile_glob(
  pattern : String,
  limits~ : @model.ResourceLimits = @model.default_limits(),
) -> @glob.GlobCompileResult {
  @glob.compile_glob(pattern, limits~)
}

///|
pub fn glob_matches(compiled : @glob.CompiledGlob, path : String) -> Bool {
  @glob.glob_matches(compiled, path)
}

///|
pub fn matches(
  pattern : String,
  path : String,
  limits~ : @model.ResourceLimits = @model.default_limits(),
) -> Bool {
  @glob.matches(pattern, path, limits~)
}

///|
pub fn config_file(path : String, text : String) -> @resolver.ConfigFile {
  @resolver.config_file(path, text)
}

///|
pub fn memory_source(
  files : Array[@resolver.ConfigFile],
) -> @resolver.MemoryConfigSource {
  @resolver.memory_source(files)
}

///|
pub fn resolve(
  target_file : String,
  source : @resolver.MemoryConfigSource,
  case_sensitivity~ : @path.CaseSensitivity = @path.CaseSensitive,
) -> @resolver.ResolveResult {
  @resolver.resolve(target_file, source, case_sensitivity)
}

///|
pub fn explain(
  target_file : String,
  source : @resolver.MemoryConfigSource,
  case_sensitivity~ : @path.CaseSensitivity = @path.CaseSensitive,
) -> @resolver.ResolveResult {
  @resolver.explain(target_file, source, case_sensitivity)
}

///|
pub fn validate(
  document : @model.EditorConfigDocument,
) -> Array[@model.Diagnostic] {
  @properties.validate_document(document)
}

///|
pub fn document_json(document : @model.EditorConfigDocument) -> String {
  @report.document_json(document)
}

///|
pub fn settings_json(settings : @model.EffectiveSettings) -> String {
  @report.settings_json(settings)
}
