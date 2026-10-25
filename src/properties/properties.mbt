///|
/// Classification of a syntactically valid EditorConfig pair.
pub(all) enum ValidationStatus {
  Valid
  Invalid
  Unset
  Custom
} derive(Eq, @debug.Debug)

///|
pub extend ValidationStatus with Eq::{not_equal, equal}

///|
pub extend ValidationStatus with @debug.Debug::{to_repr}

///|
pub(all) struct PropertyValidation {
  status : ValidationStatus
  normalized_value : String
  diagnostic : @model.Diagnostic?
} derive(Eq, @debug.Debug)

///|
pub extend PropertyValidation with Eq::{not_equal, equal}

///|
pub extend PropertyValidation with @debug.Debug::{to_repr}

///|
pub fn PropertyValidation::is_valid(self : PropertyValidation) -> Bool {
  self.status != Invalid
}

///|
pub fn PropertyValidation::is_custom(self : PropertyValidation) -> Bool {
  self.status == Custom
}

///|
pub fn known_property_names() -> Array[String] {
  [
    "indent_style", "indent_size", "tab_width", "end_of_line", "charset", "spelling_language",
    "trim_trailing_whitespace", "insert_final_newline", "root",
  ]
}

///|
pub fn is_known_property(key : String) -> Bool {
  known_property_names().contains(key.to_lower())
}

///|
fn valid_result(value : String) -> PropertyValidation {
  { status: Valid, normalized_value: value, diagnostic: None, }
}

///|
fn unset_result() -> PropertyValidation {
  { status: Unset, normalized_value: "unset", diagnostic: None, }
}

///|
fn custom_result(value : String) -> PropertyValidation {
  { status: Custom, normalized_value: value, diagnostic: None, }
}

///|
fn invalid_result(
  property : @model.Property,
  expected : String,
) -> PropertyValidation {
  let diag = @model.error_diagnostic(
    "E_PROP_VALUE",
    "unsupported value '\{property.value}' for '\{property.key}'",
    span=property.span,
    suggestion="expected \{expected} or unset",
  )
  { status: Invalid, normalized_value: property.value, diagnostic: Some(diag), }
}

///|
fn misplaced_root_result(property : @model.Property) -> PropertyValidation {
  let diag = @model.error_diagnostic(
    "E_ROOT_LOCATION",
    "root is only effective in the preamble",
    span=property.span,
    suggestion="move root before the first section header",
  )
  { status: Invalid, normalized_value: property.value, diagnostic: Some(diag), }
}

///|
fn one_of(value : String, choices : Array[String]) -> Bool {
  choices.contains(value)
}

///|
fn positive_integer(value : String) -> Int32? {
  try @string.parse_int(value) catch {
    _ => None
  } noraise {
    number if number > 0 => Some(number)
    _ => None
  }
}

///|
fn valid_language(value : String) -> Bool {
  let chars = value.to_array()
  match chars.length() {
    2 => chars[0].is_ascii_alphabetic() && chars[1].is_ascii_alphabetic()
    5 =>
      chars[0].is_ascii_alphabetic() &&
      chars[1].is_ascii_alphabetic() &&
      chars[2] == '-' &&
      chars[3].is_ascii_alphabetic() &&
      chars[4].is_ascii_alphabetic()
    _ => false
  }
}

///|
fn normalize_language(value : String) -> String {
  let chars = value.to_array()
  if chars.length() == 2 {
    value.to_lower()
  } else if chars.length() == 5 {
    let language = value.view(end_offset=2).to_owned().to_lower()
    let territory = value.view(start_offset=3).to_owned().to_upper()
    "\{language}-\{territory}"
  } else {
    value
  }
}

///|
/// Validate one pair without discarding custom keys.
pub fn validate_property(
  property : @model.Property,
  in_preamble~ : Bool = false,
) -> PropertyValidation {
  let key = property.key.to_lower()
  let raw_value = property.value
  let folded = raw_value.to_lower()
  if folded == "unset" {
    unset_result()
  } else {
    match key {
      "indent_style" =>
        if one_of(folded, ["tab", "space"]) {
          valid_result(folded)
        } else {
          invalid_result(property, "tab or space")
        }
      "indent_size" =>
        if folded == "tab" || positive_integer(folded) is Some(_) {
          valid_result(folded)
        } else {
          invalid_result(property, "a positive whole number or tab")
        }
      "tab_width" =>
        if positive_integer(folded) is Some(_) {
          valid_result(folded)
        } else {
          invalid_result(property, "a positive whole number")
        }
      "end_of_line" =>
        if one_of(folded, ["lf", "cr", "crlf"]) {
          valid_result(folded)
        } else {
          invalid_result(property, "lf, cr, or crlf")
        }
      "charset" =>
        if one_of(folded, [
            "latin1", "utf-8", "utf-8-bom", "utf-16be", "utf-16le",
          ]) {
          valid_result(folded)
        } else {
          invalid_result(
            property, "latin1, utf-8, utf-8-bom, utf-16be, or utf-16le",
          )
        }
      "trim_trailing_whitespace" | "insert_final_newline" =>
        if one_of(folded, ["true", "false"]) {
          valid_result(folded)
        } else {
          invalid_result(property, "true or false")
        }
      "spelling_language" =>
        if valid_language(raw_value) {
          valid_result(normalize_language(raw_value))
        } else {
          invalid_result(property, "an ISO language code such as en or en-US")
        }
      "root" =>
        if !in_preamble {
          misplaced_root_result(property)
        } else if one_of(folded, ["true", "false"]) {
          valid_result(folded)
        } else {
          invalid_result(property, "true or false")
        }
      _ => custom_result(raw_value)
    }
  }
}

///|
fn ignored_preamble_diagnostic(property : @model.Property) -> @model.Diagnostic {
  @model.warning_diagnostic(
    "W_PREAMBLE_IGNORED",
    "'\{property.key}' in the preamble has no effect",
    span=property.span,
    suggestion="move the pair under a section header",
  )
}

///|
fn duplicate_diagnostic(property : @model.Property) -> @model.Diagnostic {
  @model.warning_diagnostic(
    "W_DUPLICATE_PROPERTY",
    "later '\{property.key}' overrides an earlier pair in the same scope",
    span=property.span,
  )
}

///|
fn collect_scope_diagnostics(
  properties : Array[@model.Property],
  in_preamble : Bool,
  output : Array[@model.Diagnostic],
) -> Unit {
  let seen : Array[String] = []
  for property in properties {
    if seen.contains(property.key) {
      output.push(duplicate_diagnostic(property))
    } else {
      seen.push(property.key)
    }
    if in_preamble && property.key != "root" {
      output.push(ignored_preamble_diagnostic(property))
    }
    let validation = validate_property(property, in_preamble~)
    match validation.diagnostic {
      Some(diag) => output.push(diag)
      None => ()
    }
  }
}

///|
/// Validate all pairs while preserving parser diagnostics and source order.
pub fn validate_document(
  document : @model.EditorConfigDocument,
) -> Array[@model.Diagnostic] {
  let output : Array[@model.Diagnostic] = []
  collect_scope_diagnostics(document.preamble, true, output)
  for section in document.sections {
    collect_scope_diagnostics(section.properties, false, output)
  }
  output
}

///|
pub(all) struct IndentationSemantics {
  indent_style : String?
  indent_size : Int32?
  tab_width : Int32?
  indent_size_uses_tab : Bool
  uses_editor_tab_width : Bool
} derive(Eq, @debug.Debug)

///|
pub extend IndentationSemantics with Eq::{not_equal, equal}

///|
pub extend IndentationSemantics with @debug.Debug::{to_repr}

///|
fn last_value(properties : Array[@model.Property], key : String) -> String? {
  let mut result : String? = None
  for property in properties {
    if property.key == key {
      if property.is_unset() {
        result = None
      } else {
        result = Some(property.value.to_lower())
      }
    }
  }
  result
}

///|
fn optional_positive_integer(value : String?) -> Int32? {
  match value {
    Some(text) => positive_integer(text)
    None => None
  }
}

///|
/// Interpret the three indentation properties after ordinary precedence has
/// selected their latest values.
pub fn indentation_semantics(
  properties : Array[@model.Property],
) -> IndentationSemantics {
  let indent_style = last_value(properties, "indent_style")
  let indent_size_text = last_value(properties, "indent_size")
  let tab_width_text = last_value(properties, "tab_width")
  let tab_width = optional_positive_integer(tab_width_text)
  match indent_size_text {
    Some("tab") =>
      {
        indent_style,
        indent_size: tab_width,
        tab_width,
        indent_size_uses_tab: true,
        uses_editor_tab_width: tab_width is None,
      }
    Some(number) =>
      {
        indent_style,
        indent_size: positive_integer(number),
        tab_width: match tab_width {
          Some(width) => Some(width)
          None => positive_integer(number)
        },
        indent_size_uses_tab: false,
        uses_editor_tab_width: false,
      }
    None =>
      {
        indent_style,
        indent_size: None,
        tab_width,
        indent_size_uses_tab: false,
        uses_editor_tab_width: false,
      }
  }
}

///|
pub fn normalized_property(
  property : @model.Property,
  in_preamble~ : Bool = false,
) -> @model.Property {
  let validation = validate_property(property, in_preamble~)
  @model.property(
    property.raw_key,
    property.key.to_lower(),
    property.raw_value,
    validation.normalized_value,
    property.span,
    property.ordinal,
  )
}
