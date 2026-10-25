///|
/// A host failure is kept separate from parser diagnostics so callers can
/// distinguish inaccessible files from invalid EditorConfig contents.
pub(all) struct HostError {
  operation : String
  path : String
  message : String
} derive(Eq, @debug.Debug)

///|
pub(all) struct ConfigLoadResult {
  source : @resolver.MemoryConfigSource
  diagnostics : Array[@model.Diagnostic]
  errors : Array[HostError]
  discovered_paths : Array[String]
} derive(Eq, @debug.Debug)

///|
pub fn host_error(
  operation : String,
  path : String,
  message : String,
) -> HostError {
  { operation, path, message, }
}

///|
pub fn HostError::render(self : HostError) -> String {
  self.operation + " '" + self.path + "': " + self.message
}

///|
/// Read bytes without relying on lossy host decoding. The parser's UTF-8
/// decoder therefore remains the single source of encoding diagnostics.
pub async fn read_bytes(path : String) -> Result[Bytes, HostError] {
  Ok(@fs.read_file(path).binary()) catch {
    error => Err(host_error("read", path, error.to_string()))
  }
}

///|
pub async fn read_utf8(
  path : String,
) -> Result[String, (@model.Diagnostic, HostError?)] {
  match read_bytes(path) {
    Err(error) =>
      Err(
        (
          @model.error_diagnostic(
            "E_IO_READ",
            error.render(),
            span=@model.unknown_span(path),
          ),
          Some(error),
        ),
      )
    Ok(bytes) =>
      match @lexer.decode_utf8(bytes.exact_view(), source=path) {
        Ok(text) => Ok(text)
        Err(diagnostic) => Err((diagnostic, None))
      }
  }
}

///|
async fn host_exists(path : String) -> Result[Bool, HostError] {
  Ok(@fs.exists(path)) catch {
    error => Err(host_error("inspect", path, error.to_string()))
  }
}

///|
/// Discover every lexical candidate on disk and load valid UTF-8 contents
/// into the pure resolver's memory source. Missing candidates are normal;
/// permission and decoding failures remain observable in separate arrays.
pub async fn load_config_source(
  target_file : String,
  config_name~ : String = ".editorconfig",
) -> ConfigLoadResult {
  let source = @resolver.empty_memory_source()
  let diagnostics : Array[@model.Diagnostic] = []
  let errors : Array[HostError] = []
  let discovered_paths : Array[String] = []
  for candidate in @path.config_candidates(target_file, config_name~) {
    match host_exists(candidate) {
      Err(error) => errors.push(error)
      Ok(false) => ()
      Ok(true) =>
        match read_utf8(candidate) {
          Ok(text) => {
            source.put(candidate, text)
            discovered_paths.push(candidate)
            if @parser.parse(text, source=candidate).stops_search() {
              break
            }
          }
          Err((diagnostic, host_failure)) => {
            diagnostics.push(diagnostic)
            match host_failure {
              Some(error) => errors.push(error)
              None => ()
            }
          }
        }
    }
  }
  { source, diagnostics, errors, discovered_paths, }
}

///|
pub extend HostError with Eq::{not_equal, equal}

///|
pub extend HostError with @debug.Debug::{to_repr}

///|
pub extend ConfigLoadResult with Eq::{not_equal, equal}

///|
pub extend ConfigLoadResult with @debug.Debug::{to_repr}
