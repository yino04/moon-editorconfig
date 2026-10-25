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
fn string_option_json(value : String?) -> String {
  match value {
    Some(text) => json_string(text)
    None => "null"
  }
}

///|
fn join_json(values : Array[String]) -> String {
  "[" + values.join(",") + "]"
}

///|
pub fn position_json(position : @model.SourcePos) -> String {
  "{" +
  "\"offset\":" +
  "\{position.offset}" +
  ",\"line\":" +
  "\{position.line}" +
  ",\"column\":" +
  "\{position.column}" +
  "}"
}

///|
pub fn span_json(span : @model.SourceSpan) -> String {
  "{" +
  "\"source\":" +
  json_string(span.source) +
  ",\"start\":" +
  position_json(span.start) +
  ",\"end\":" +
  position_json(span.end) +
  "}"
}

///|
fn span_option_json(span : @model.SourceSpan?) -> String {
  match span {
    Some(value) => span_json(value)
    None => "null"
  }
}

///|
pub fn diagnostic_json(diagnostic : @model.Diagnostic) -> String {
  "{" +
  "\"severity\":" +
  json_string(diagnostic.severity.label()) +
  ",\"code\":" +
  json_string(diagnostic.code) +
  ",\"message\":" +
  json_string(diagnostic.message) +
  ",\"suggestion\":" +
  string_option_json(diagnostic.suggestion) +
  ",\"span\":" +
  span_option_json(diagnostic.span) +
  "}"
}

///|
pub fn diagnostics_json(diagnostics : Array[@model.Diagnostic]) -> String {
  join_json(diagnostics.map(fn(item) { diagnostic_json(item) }))
}

///|
pub fn property_json(property : @model.Property) -> String {
  "{" +
  "\"rawKey\":" +
  json_string(property.raw_key) +
  ",\"key\":" +
  json_string(property.key) +
  ",\"rawValue\":" +
  json_string(property.raw_value) +
  ",\"value\":" +
  json_string(property.value) +
  ",\"ordinal\":" +
  "\{property.ordinal}" +
  ",\"span\":" +
  span_json(property.span) +
  "}"
}

///|
fn properties_json(properties : Array[@model.Property]) -> String {
  join_json(properties.map(fn(item) { property_json(item) }))
}

///|
pub fn section_json(section : @model.Section) -> String {
  "{" +
  "\"rawGlob\":" +
  json_string(section.raw_glob) +
  ",\"glob\":" +
  json_string(section.glob) +
  ",\"ordinal\":" +
  "\{section.ordinal}" +
  ",\"span\":" +
  span_json(section.span) +
  ",\"properties\":" +
  properties_json(section.properties) +
  "}"
}

///|
fn sections_json(sections : Array[@model.Section]) -> String {
  join_json(sections.map(fn(item) { section_json(item) }))
}

///|
/// Stable compact JSON for a parsed document. Field order is part of the CLI
/// contract so repeated runs over the same input are byte-for-byte identical.
pub fn document_json(document : @model.EditorConfigDocument) -> String {
  "{" +
  "\"source\":" +
  json_string(document.source) +
  ",\"specVersion\":" +
  json_string(@model.V0_17_2.to_string()) +
  ",\"hasBom\":" +
  json_bool(document.has_bom) +
  ",\"lineEnding\":" +
  json_string(document.line_ending.label()) +
  ",\"preamble\":" +
  properties_json(document.preamble) +
  ",\"sections\":" +
  sections_json(document.sections) +
  ",\"diagnostics\":" +
  diagnostics_json(document.diagnostics) +
  "}"
}

///|
pub fn effective_property_json(property : @model.EffectiveProperty) -> String {
  "{" +
  "\"key\":" +
  json_string(property.key) +
  ",\"value\":" +
  json_string(property.value) +
  ",\"configPath\":" +
  json_string(property.config_path) +
  ",\"sectionGlob\":" +
  json_string(property.section_glob) +
  ",\"span\":" +
  span_json(property.span) +
  "}"
}

///|
fn effective_properties_json(
  properties : Array[@model.EffectiveProperty],
) -> String {
  join_json(properties.map(fn(item) { effective_property_json(item) }))
}

///|
pub fn trace_event_json(event : @model.TraceEvent) -> String {
  "{" +
  "\"action\":" +
  json_string(event.action.label()) +
  ",\"key\":" +
  json_string(event.key) +
  ",\"value\":" +
  json_string(event.value) +
  ",\"configPath\":" +
  json_string(event.config_path) +
  ",\"sectionGlob\":" +
  json_string(event.section_glob) +
  ",\"span\":" +
  span_json(event.span) +
  ",\"note\":" +
  json_string(event.note) +
  "}"
}

///|
fn trace_json(events : Array[@model.TraceEvent]) -> String {
  join_json(events.map(fn(item) { trace_event_json(item) }))
}

///|
pub fn settings_json(settings : @model.EffectiveSettings) -> String {
  "{" +
  "\"targetPath\":" +
  json_string(settings.target_path) +
  ",\"properties\":" +
  effective_properties_json(settings.properties) +
  ",\"diagnostics\":" +
  diagnostics_json(settings.diagnostics) +
  ",\"trace\":" +
  trace_json(settings.trace) +
  "}"
}

///|
pub fn diagnostic_text(diagnostic : @model.Diagnostic) -> String {
  let base = "\{diagnostic.location_label()}: \{diagnostic.severity.label()} [\{diagnostic.code}]: \{diagnostic.message}"
  match diagnostic.suggestion {
    Some(suggestion) => base + "\n  help: " + suggestion
    None => base
  }
}

///|
pub fn diagnostics_text(diagnostics : Array[@model.Diagnostic]) -> String {
  diagnostics.map(fn(item) { diagnostic_text(item) }).join("\n")
}

///|
pub fn settings_text(settings : @model.EffectiveSettings) -> String {
  let lines : Array[String] = []
  for property in settings.properties {
    lines.push(
      "\{property.key}=\{property.value} # \{property.config_path} [\{property.section_glob}]",
    )
  }
  lines.join("\n")
}
