///|
fn command_arguments() -> Array[String] {
  let process_arguments = @env.args()
  let command_arguments : Array[String] = []
  for index = 1; index < process_arguments.length(); index = index + 1 {
    command_arguments.push(process_arguments[index])
  }
  command_arguments
}

///|
fn case_sensitivity(path : String) -> @path.CaseSensitivity {
  match @path.path_kind(path) {
    @path.DriveRelativePath(_)
    | @path.DriveAbsolutePath(_)
    | @path.UncPath(_, _) => @path.AsciiCaseInsensitive
    _ => @path.CaseSensitive
  }
}

///|
fn early_load_failure(
  loaded : @io.ConfigLoadResult,
  json : Bool,
) -> @cli.CliResponse? {
  if !loaded.errors.is_empty() {
    let error = loaded.errors[0]
    Some(@cli.io_error_response(error.path, error.message, json))
  } else {
    None
  }
}

///|
fn append_load_diagnostics(
  result : @resolver.ResolveResult,
  diagnostics : Array[@model.Diagnostic],
) -> Unit {
  for diagnostic in diagnostics {
    result.settings.diagnostics.push(diagnostic)
  }
}

///|
async fn dispatch(command : @cli.CliCommand) -> @cli.CliResponse {
  match command {
    Help => @cli.help_response()
    Version => @cli.version_response()
    Parse(path, json) =>
      match @io.read_utf8(path) {
        Ok(text) => @cli.parse_response(text, path, json)
        Err((_, Some(error))) =>
          @cli.io_error_response(error.path, error.message, json)
        Err((diagnostic, None)) => @cli.diagnostics_response([diagnostic], json)
      }
    Match(pattern, path, json) => @cli.match_response(pattern, path, json)
    Validate(path, strict, json) =>
      match @io.read_utf8(path) {
        Ok(text) => @cli.validate_response(text, path, strict, json)
        Err((_, Some(error))) =>
          @cli.io_error_response(error.path, error.message, json)
        Err((diagnostic, None)) => @cli.diagnostics_response([diagnostic], json)
      }
    Resolve(target, json) => {
      let loaded = @io.load_config_source(target)
      match early_load_failure(loaded, json) {
        Some(response) => response
        None => {
          let result = @resolver.resolve(
            target,
            loaded.source,
            case_sensitivity(target),
          )
          append_load_diagnostics(result, loaded.diagnostics)
          @cli.resolve_response(result, false, json)
        }
      }
    }
    Explain(target, json) => {
      let loaded = @io.load_config_source(target)
      match early_load_failure(loaded, json) {
        Some(response) => response
        None => {
          let result = @resolver.explain(
            target,
            loaded.source,
            case_sensitivity(target),
          )
          append_load_diagnostics(result, loaded.diagnostics)
          @cli.resolve_response(result, true, json)
        }
      }
    }
  }
}

///|
async fn emit(response : @cli.CliResponse) -> Unit {
  if response.stdout != "" {
    @stdio.stdout.write(response.stdout)
  }
  if response.stderr != "" {
    @stdio.stderr.write(response.stderr)
  }
}

///|
async fn main {
  let response = match @cli.parse_arguments(command_arguments()) {
    Ok(command) => dispatch(command)
    Err(error) => @cli.usage_response(error)
  }
  emit(response)
  if response.exit_code != @cli.exit_success() {
    process_exit(response.exit_code)
  }
}
