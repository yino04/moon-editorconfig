///|
/// Parsed command line. Paths remain lexical strings until the host adapter
/// reads them; the pure CLI layer never opens files or consults the process.
pub(all) enum CliCommand {
  Help
  Version
  Parse(String, Bool)
  Match(String, String, Bool)
  Resolve(String, Bool)
  Explain(String, Bool)
  Validate(String, Bool, Bool)
} derive(Eq, @debug.Debug)

///|
pub(all) struct CliUsageError {
  message : String
} derive(Eq, @debug.Debug)

///|
pub(all) struct CliResponse {
  stdout : String
  stderr : String
  exit_code : Int32
} derive(Eq, @debug.Debug)

///|
priv struct TailArguments {
  positionals : Array[String]
  json : Bool
  strict : Bool
  help : Bool
}

///|
pub fn exit_success() -> Int32 {
  0
}

///|
pub fn exit_usage() -> Int32 {
  2
}

///|
pub fn exit_invalid_config() -> Int32 {
  3
}

///|
pub fn exit_io() -> Int32 {
  4
}

///|
pub fn exit_resource_limit() -> Int32 {
  5
}

///|
pub fn version_text() -> String {
  "moonecfg 0.1.0"
}

///|
pub fn help_text() -> String {
  (
    #|MoonEditorConfig query tool
    #|
    #|Usage:
    #|  moonecfg parse <config-file> [--json]
    #|  moonecfg match <pattern> <relative-path> [--json]
    #|  moonecfg resolve <target-file> [--json]
    #|  moonecfg explain <target-file> [--json]
    #|  moonecfg validate <config-file> [--strict] [--json]
    #|  moonecfg --help
    #|  moonecfg --version
    #|
    #|Exit codes: 0 success, 2 usage, 3 invalid configuration,
    #|            4 host I/O failure, 5 resource budget exhausted.
  )
}

///|
fn usage_error(message : String) -> Result[CliCommand, CliUsageError] {
  Err({ message, })
}

///|
fn parse_tail(
  args : Array[String],
  start : Int32,
) -> Result[TailArguments, CliUsageError] {
  let positionals : Array[String] = []
  let mut json = false
  let mut strict = false
  let mut help = false
  let mut accept_options = true
  for index = start; index < args.length(); index = index + 1 {
    let argument = args[index]
    if accept_options && argument == "--" {
      accept_options = false
    } else if accept_options && argument == "--json" {
      json = true
    } else if accept_options && argument == "--strict" {
      strict = true
    } else if accept_options && (argument == "--help" || argument == "-h") {
      help = true
    } else if accept_options && argument.has_prefix("-") {
      return Err({ message: "unknown option: " + argument, })
    } else {
      positionals.push(argument)
    }
  }
  Ok({ positionals, json, strict, help, })
}

///|
fn require_count(
  command : String,
  actual : Int32,
  expected : Int32,
) -> Result[Unit, CliUsageError] {
  if actual == expected {
    Ok(())
  } else {
    Err({
      message: command +
      " expects " +
      expected.to_string() +
      " positional argument(s), got " +
      actual.to_string(),
    })
  }
}

///|
/// Parse arguments after the executable name. `--` ends option processing, so
/// a pattern or path beginning with a hyphen can still be supplied exactly.
pub fn parse_arguments(
  args : Array[String],
) -> Result[CliCommand, CliUsageError] {
  if args.is_empty() {
    return Ok(Help)
  }
  let first = args[0]
  if first == "--help" || first == "-h" || first == "help" {
    return Ok(Help)
  }
  if first == "--version" || first == "-V" || first == "version" {
    return Ok(Version)
  }
  let tail = match parse_tail(args, 1) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if tail.help {
    return Ok(Help)
  }
  match first {
    "parse" => {
      if tail.strict {
        return usage_error("--strict is only valid with validate")
      }
      match require_count("parse", tail.positionals.length(), 1) {
        Err(error) => Err(error)
        Ok(_) => Ok(Parse(tail.positionals[0], tail.json))
      }
    }
    "match" => {
      if tail.strict {
        return usage_error("--strict is only valid with validate")
      }
      match require_count("match", tail.positionals.length(), 2) {
        Err(error) => Err(error)
        Ok(_) => Ok(Match(tail.positionals[0], tail.positionals[1], tail.json))
      }
    }
    "resolve" => {
      if tail.strict {
        return usage_error("--strict is only valid with validate")
      }
      match require_count("resolve", tail.positionals.length(), 1) {
        Err(error) => Err(error)
        Ok(_) => Ok(Resolve(tail.positionals[0], tail.json))
      }
    }
    "explain" => {
      if tail.strict {
        return usage_error("--strict is only valid with validate")
      }
      match require_count("explain", tail.positionals.length(), 1) {
        Err(error) => Err(error)
        Ok(_) => Ok(Explain(tail.positionals[0], tail.json))
      }
    }
    "validate" =>
      match require_count("validate", tail.positionals.length(), 1) {
        Err(error) => Err(error)
        Ok(_) => Ok(Validate(tail.positionals[0], tail.strict, tail.json))
      }
    command => usage_error("unknown command: " + command)
  }
}

///|
fn terminated(value : String) -> String {
  if value == "" || value.has_suffix("\n") {
    value
  } else {
    value + "\n"
  }
}

///|
fn json_string(value : String) -> String {
  @json.to_json(value).stringify()
}

///|
fn json_bool(value : Bool) -> String {
  if value {
    "true"
  } else {
    "false"
  }
}

///|
fn string_array_json(values : Array[String]) -> String {
  "[" + values.map(fn(value) { json_string(value) }).join(",") + "]"
}

///|
fn string_option_json(value : String?) -> String {
  match value {
    Some(text) => json_string(text)
    None => "null"
  }
}

///|
fn has_error(diagnostics : Array[@model.Diagnostic]) -> Bool {
  diagnostics.any(fn(diagnostic) { diagnostic.is_error() })
}

///|
fn is_resource_code(code : String) -> Bool {
  code.contains("LIMIT") ||
  code == "E_GLOB_LENGTH" ||
  code == "E_DOCUMENT_LENGTH"
}

///|
fn diagnostic_exit_code(diagnostics : Array[@model.Diagnostic]) -> Int32 {
  if diagnostics.any(fn(diagnostic) { is_resource_code(diagnostic.code) }) {
    exit_resource_limit()
  } else if has_error(diagnostics) {
    exit_invalid_config()
  } else {
    exit_success()
  }
}

///|
fn plain_diagnostics(diagnostics : Array[@model.Diagnostic]) -> String {
  if diagnostics.is_empty() {
    ""
  } else {
    terminated(@report.diagnostics_text(diagnostics))
  }
}

///|
pub fn help_response() -> CliResponse {
  { stdout: terminated(help_text()), stderr: "", exit_code: exit_success(), }
}

///|
pub fn version_response() -> CliResponse {
  { stdout: terminated(version_text()), stderr: "", exit_code: exit_success(), }
}

///|
pub fn usage_response(error : CliUsageError) -> CliResponse {
  {
    stdout: "",
    stderr: terminated("error: " + error.message + "\n\n" + help_text()),
    exit_code: exit_usage(),
  }
}

///|
/// Render diagnostics produced before a document can be built, most notably
/// invalid UTF-8 from the host byte reader. JSON mode stays machine-clean.
pub fn diagnostics_response(
  diagnostics : Array[@model.Diagnostic],
  json : Bool,
) -> CliResponse {
  {
    stdout: if json {
      terminated(
        "{" +
        "\"valid\":false,\"diagnostics\":" +
        @report.diagnostics_json(diagnostics) +
        "}",
      )
    } else {
      ""
    },
    stderr: if json {
      ""
    } else {
      plain_diagnostics(diagnostics)
    },
    exit_code: diagnostic_exit_code(diagnostics),
  }
}

///|
fn document_text(document : @model.EditorConfigDocument) -> String {
  let lines = [
    "source: " + document.source,
    "spec: " + @model.V0_17_2.to_string(),
    "preamble-properties: " + document.preamble.length().to_string(),
    "sections: " + document.sections.length().to_string(),
    "properties: " + document.property_count().to_string(),
    "diagnostics: " + document.diagnostics.length().to_string(),
  ]
  terminated(lines.join("\n"))
}

///|
pub fn parse_response(
  text : String,
  source : String,
  json : Bool,
) -> CliResponse {
  let document = @parser.parse(text, source~)
  let stdout = if json {
    terminated(@report.document_json(document))
  } else {
    document_text(document)
  }
  {
    stdout,
    stderr: if json {
      ""
    } else {
      plain_diagnostics(document.diagnostics)
    },
    exit_code: diagnostic_exit_code(document.diagnostics),
  }
}

///|
fn validated_document(
  text : String,
  source : String,
  strict : Bool,
) -> @model.EditorConfigDocument {
  let options = if strict {
    @model.strict_parse_options()
  } else {
    @model.default_parse_options()
  }
  let parsed = @parser.parse(text, source~, options~)
  let diagnostics = parsed.diagnostics.copy()
  for diagnostic in @properties.validate_document(parsed) {
    diagnostics.push(diagnostic)
  }
  @model.document(
    parsed.source,
    parsed.preamble,
    parsed.sections,
    diagnostics,
    parsed.has_bom,
    parsed.line_ending,
  )
}

///|
pub fn validate_response(
  text : String,
  source : String,
  strict : Bool,
  json : Bool,
) -> CliResponse {
  let document = validated_document(text, source, strict)
  let valid = !document.has_errors()
  let stdout = if json {
    terminated(
      "{" +
      "\"valid\":" +
      json_bool(valid) +
      ",\"strict\":" +
      json_bool(strict) +
      ",\"document\":" +
      @report.document_json(document) +
      "}",
    )
  } else if valid {
    "valid\n"
  } else {
    "invalid\n"
  }
  {
    stdout,
    stderr: if json {
      ""
    } else {
      plain_diagnostics(document.diagnostics)
    },
    exit_code: diagnostic_exit_code(document.diagnostics),
  }
}

///|
fn match_json(
  pattern : String,
  path : String,
  result : @glob.GlobMatchResult,
) -> String {
  "{" +
  "\"pattern\":" +
  json_string(pattern) +
  ",\"path\":" +
  json_string(path) +
  ",\"matched\":" +
  json_bool(result.matched) +
  ",\"operations\":" +
  result.operations.to_string() +
  ",\"exhausted\":" +
  json_bool(result.exhausted) +
  ",\"diagnostics\":" +
  @report.diagnostics_json(result.diagnostics) +
  "}"
}

///|
pub fn match_response(
  pattern : String,
  path : String,
  json : Bool,
) -> CliResponse {
  let compiled = @glob.compile_glob(pattern)
  guard compiled.glob is Some(glob) else {
    return {
      stdout: if json {
        terminated(
          "{" +
          "\"pattern\":" +
          json_string(pattern) +
          ",\"path\":" +
          json_string(path) +
          ",\"matched\":false,\"operations\":0,\"exhausted\":false" +
          ",\"diagnostics\":" +
          @report.diagnostics_json(compiled.diagnostics) +
          "}",
        )
      } else {
        "false\n"
      },
      stderr: if json {
        ""
      } else {
        plain_diagnostics(compiled.diagnostics)
      },
      exit_code: diagnostic_exit_code(compiled.diagnostics),
    }
  }
  let result = @glob.match_glob(glob, path)
  {
    stdout: if json {
      terminated(match_json(pattern, path, result))
    } else if result.matched {
      "true\n"
    } else {
      "false\n"
    },
    stderr: if json {
      ""
    } else {
      plain_diagnostics(result.diagnostics)
    },
    exit_code: diagnostic_exit_code(result.diagnostics),
  }
}

///|
fn trace_text(events : Array[@model.TraceEvent]) -> String {
  let lines : Array[String] = []
  for event in events {
    lines.push(
      event.action.label() +
      " " +
      event.key +
      "=" +
      event.value +
      " <- " +
      event.config_path +
      " [" +
      event.section_glob +
      "] (" +
      event.note +
      ")",
    )
  }
  lines.join("\n")
}

///|
fn resolve_json(mode : String, result : @resolver.ResolveResult) -> String {
  "{" +
  "\"mode\":" +
  json_string(mode) +
  ",\"searchedConfigPaths\":" +
  string_array_json(result.searched_config_paths) +
  ",\"loadedConfigPaths\":" +
  string_array_json(result.loaded_config_paths) +
  ",\"stoppedByRoot\":" +
  string_option_json(result.stopped_by_root) +
  ",\"settings\":" +
  @report.settings_json(result.settings) +
  "}"
}

///|
pub fn resolve_response(
  result : @resolver.ResolveResult,
  explain : Bool,
  json : Bool,
) -> CliResponse {
  let mode = if explain { "explain" } else { "resolve" }
  let stdout = if json {
    terminated(resolve_json(mode, result))
  } else {
    let settings = @report.settings_text(result.settings)
    let trace = if explain { trace_text(result.settings.trace) } else { "" }
    let combined = if settings == "" {
      trace
    } else if trace == "" {
      settings
    } else {
      settings + "\n\ntrace:\n" + trace
    }
    terminated(combined)
  }
  {
    stdout,
    stderr: if json {
      ""
    } else {
      plain_diagnostics(result.settings.diagnostics)
    },
    exit_code: diagnostic_exit_code(result.settings.diagnostics),
  }
}

///|
pub fn io_error_response(
  path : String,
  message : String,
  json : Bool,
) -> CliResponse {
  let text = "cannot read '" + path + "': " + message
  if json {
    {
      stdout: terminated(
        "{" +
        "\"error\":\"io\",\"path\":" +
        json_string(path) +
        ",\"message\":" +
        json_string(message) +
        "}",
      ),
      stderr: "",
      exit_code: exit_io(),
    }
  } else {
    { stdout: "", stderr: terminated("error: " + text), exit_code: exit_io(), }
  }
}

///|
pub extend CliCommand with Eq::{not_equal, equal}

///|
pub extend CliCommand with @debug.Debug::{to_repr}

///|
pub extend CliUsageError with Eq::{not_equal, equal}

///|
pub extend CliUsageError with @debug.Debug::{to_repr}

///|
pub extend CliResponse with Eq::{not_equal, equal}

///|
pub extend CliResponse with @debug.Debug::{to_repr}
