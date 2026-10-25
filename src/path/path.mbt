///|
/// The lexical anchor carried by a normalized path. Drive-relative paths such
/// as `C:src/main.mbt` are deliberately distinct from drive-absolute paths
/// such as `C:/src/main.mbt`.
pub(all) enum PathKind {
  RelativePath
  RootedPath
  DriveRelativePath(String)
  DriveAbsolutePath(String)
  UncPath(String, String)
} derive(Eq, @debug.Debug)

///|
/// Comparison never consults the host operating system. Callers must choose
/// whether path roots and components are compared exactly or with ASCII case
/// folding.
pub(all) enum CaseSensitivity {
  CaseSensitive
  AsciiCaseInsensitive
} derive(Eq, @debug.Debug)

///|
/// A parsed, purely lexical path. Components contain neither separators nor
/// `.`. Absolute paths also never retain `..`; relative paths retain only the
/// leading `..` components that cannot be folded.
pub struct LexicalPath {
  kind : PathKind
  components : Array[String]
} derive(Eq, @debug.Debug)

///|
fn slashify(value : String) -> String {
  value.replace_all(old="\\", new="/")
}

///|
fn is_ascii_letter(unit : UInt16) -> Bool {
  (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A)
}

///|
fn has_drive_prefix(value : String) -> Bool {
  value.length() >= 2 && is_ascii_letter(value[0]) && value[1] == 0x3A
}

///|
fn leading_slashes(value : String) -> Int32 {
  let mut count = 0
  while count < value.length() && value[count] == 0x2F {
    count += 1
  }
  count
}

///|
fn raw_components(value : String, start : Int32) -> Array[String] {
  let output : Array[String] = []
  if start < value.length() {
    for component in value[start:].split("/") {
      let owned = component.to_owned()
      if owned != "" {
        output.push(owned)
      }
    }
  }
  output
}

///|
fn is_anchored(kind : PathKind) -> Bool {
  match kind {
    RootedPath | DriveAbsolutePath(_) | UncPath(_, _) => true
    RelativePath | DriveRelativePath(_) => false
  }
}

///|
fn fold_component(
  output : Array[String],
  component : String,
  anchored : Bool,
) -> Unit {
  if component == "" || component == "." {
    return
  }
  if component == ".." {
    match output.last() {
      Some(last) if last != ".." => {
        let _ = output.pop()
      }
      _ => if !anchored { output.push(component) }
    }
  } else {
    output.push(component)
  }
}

///|
fn normalize_components(raw : Array[String], anchored : Bool) -> Array[String] {
  let output : Array[String] = []
  for component in raw {
    fold_component(output, component, anchored)
  }
  output
}

///|
fn parse_unc(value : String, slash_count : Int32) -> LexicalPath? {
  if slash_count < 2 {
    return None
  }
  let raw = raw_components(value, slash_count)
  if raw.length() < 2 ||
    raw[0] == "." ||
    raw[0] == ".." ||
    raw[1] == "." ||
    raw[1] == ".." {
    None
  } else {
    let tail : Array[String] = []
    for index = 2; index < raw.length(); index = index + 1 {
      tail.push(raw[index])
    }
    Some({
      kind: UncPath(raw[0], raw[1]),
      components: normalize_components(tail, true),
    })
  }
}

///|
/// Parse and normalize a path without touching the filesystem. Both slash
/// spellings are accepted. A complete `//server/share` prefix is recognized
/// as UNC; an incomplete double-slash prefix is treated as an ordinary rooted
/// path.
pub fn parse(value : String) -> LexicalPath {
  let slashed = slashify(value)
  if has_drive_prefix(slashed) {
    let drive = slashed[0:2].to_owned()
    if slashed.length() >= 3 && slashed[2] == 0x2F {
      let start = 2 + leading_slashes(slashed[2:].to_owned())
      let kind = DriveAbsolutePath(drive)
      {
        kind,
        components: normalize_components(raw_components(slashed, start), true),
      }
    } else {
      let kind = DriveRelativePath(drive)
      {
        kind,
        components: normalize_components(raw_components(slashed, 2), false),
      }
    }
  } else {
    let slash_count = leading_slashes(slashed)
    match parse_unc(slashed, slash_count) {
      Some(path) => path
      None =>
        if slash_count > 0 {
          {
            kind: RootedPath,
            components: normalize_components(
              raw_components(slashed, slash_count),
              true,
            ),
          }
        } else {
          {
            kind: RelativePath,
            components: normalize_components(raw_components(slashed, 0), false),
          }
        }
    }
  }
}

///|
pub fn LexicalPath::path_kind(self : LexicalPath) -> PathKind {
  self.kind
}

///|
/// Return a copy so callers cannot mutate the normalized representation.
pub fn LexicalPath::parts(self : LexicalPath) -> Array[String] {
  self.components.copy()
}

///|
pub fn LexicalPath::is_absolute(self : LexicalPath) -> Bool {
  is_anchored(self.kind)
}

///|
pub fn LexicalPath::is_relative(self : LexicalPath) -> Bool {
  !self.is_absolute()
}

///|
pub fn LexicalPath::root_name(self : LexicalPath) -> String {
  match self.kind {
    RelativePath => ""
    RootedPath => "/"
    DriveRelativePath(drive) => drive
    DriveAbsolutePath(drive) => drive + "/"
    UncPath(server, share) => "//" + server + "/" + share
  }
}

///|
pub fn LexicalPath::render(self : LexicalPath) -> String {
  let tail = self.components.join("/")
  match self.kind {
    RelativePath => if tail == "" { "." } else { tail }
    RootedPath => if tail == "" { "/" } else { "/" + tail }
    DriveRelativePath(drive) => drive + tail
    DriveAbsolutePath(drive) =>
      if tail == "" {
        drive + "/"
      } else {
        drive + "/" + tail
      }
    UncPath(server, share) => {
      let root = "//" + server + "/" + share
      if tail == "" {
        root
      } else {
        root + "/" + tail
      }
    }
  }
}

///|
/// Convert separators, collapse duplicate separators, remove `.`, and fold
/// `..` without allowing an absolute path to escape its lexical root.
pub fn normalize(value : String) -> String {
  parse(value).render()
}

///|
pub fn path_kind(value : String) -> PathKind {
  parse(value).path_kind()
}

///|
pub fn is_absolute(value : String) -> Bool {
  parse(value).is_absolute()
}

///|
pub fn is_relative(value : String) -> Bool {
  parse(value).is_relative()
}

///|
/// Return the drive prefix including its colon, for example `C:`.
pub fn drive(value : String) -> String? {
  match parse(value).kind {
    DriveRelativePath(prefix) | DriveAbsolutePath(prefix) => Some(prefix)
    RelativePath | RootedPath | UncPath(_, _) => None
  }
}

///|
pub fn is_unc(value : String) -> Bool {
  parse(value).kind is UncPath(_, _)
}

///|
pub fn unc_server(value : String) -> String? {
  match parse(value).kind {
    UncPath(server, _) => Some(server)
    _ => None
  }
}

///|
pub fn unc_share(value : String) -> String? {
  match parse(value).kind {
    UncPath(_, share) => Some(share)
    _ => None
  }
}

///|
fn names_equal(left : String, right : String, case : CaseSensitivity) -> Bool {
  match case {
    CaseSensitive => left == right
    AsciiCaseInsensitive => left.equal_ignore_ascii_case(right)
  }
}

///|
fn roots_equal(
  left : PathKind,
  right : PathKind,
  case : CaseSensitivity,
) -> Bool {
  match (left, right) {
    (RelativePath, RelativePath) | (RootedPath, RootedPath) => true
    (DriveRelativePath(a), DriveRelativePath(b))
    | (DriveAbsolutePath(a), DriveAbsolutePath(b)) => names_equal(a, b, case)
    (UncPath(a_server, a_share), UncPath(b_server, b_share)) =>
      names_equal(a_server, b_server, case) &&
      names_equal(a_share, b_share, case)
    _ => false
  }
}

///|
fn component_prefix_length(
  left : Array[String],
  right : Array[String],
  case : CaseSensitivity,
) -> Int32 {
  let limit = left.length().min(right.length())
  let mut count = 0
  while count < limit && names_equal(left[count], right[count], case) {
    count += 1
  }
  count
}

///|
/// Compare two normalized lexical paths using the caller-selected case rule.
pub fn path_equal(
  left : String,
  right : String,
  case : CaseSensitivity,
) -> Bool {
  let a = parse(left)
  let b = parse(right)
  roots_equal(a.kind, b.kind, case) &&
  a.components.length() == b.components.length() &&
  component_prefix_length(a.components, b.components, case) ==
  a.components.length()
}

///|
/// Return the lexical parent. Root anchors and the relative current directory
/// are stable under `dirname`.
pub fn dirname(value : String) -> String {
  let path = parse(value)
  let components = path.components.copy()
  if components.length() > 0 {
    let _ = components.pop()
  }
  ({ kind: path.kind, components, } : LexicalPath).render()
}

///|
/// Return the last normalized component. Root anchors have an empty basename;
/// the empty/current relative path has basename `.`.
pub fn basename(value : String) -> String {
  let path = parse(value)
  match path.components.last() {
    Some(component) => component
    None =>
      match path.kind {
        RelativePath => "."
        _ => ""
      }
  }
}

///|
/// Join two lexical paths. A rooted, drive-prefixed, or UNC right operand
/// replaces the left operand. A relative right operand is folded against the
/// left operand's components.
pub fn join(base : String, child : String) -> String {
  let left = parse(base)
  let right = parse(child)
  match right.kind {
    RelativePath => {
      let components = left.components.copy()
      let anchored = is_anchored(left.kind)
      for component in right.components {
        fold_component(components, component, anchored)
      }
      ({ kind: left.kind, components, } : LexicalPath).render()
    }
    _ => right.render()
  }
}

///|
/// Join zero or more lexical path fragments. The identity is `.`.
pub fn join_many(values : Array[String]) -> String {
  let mut output = "."
  for value in values {
    output = join(output, value)
  }
  output
}

///|
/// Enumerate a normalized path and each lexical parent, nearest first. The
/// root anchor (or `.` for an ordinary relative path) is included exactly once.
pub fn ancestors(value : String) -> Array[String] {
  let path = parse(value)
  let components = path.components.copy()
  let output : Array[String] = []
  while true {
    output.push(
      ({ kind: path.kind, components: components.copy(), } : LexicalPath).render(),
    )
    if components.length() == 0 {
      break
    }
    let _ = components.pop()
  }
  output
}

///|
/// Produce the directory walk used to discover `.editorconfig` files for a
/// target file. The target's containing directory comes first and the lexical
/// root/current directory comes last.
pub fn config_search_directories(target_file : String) -> Array[String] {
  ancestors(dirname(target_file))
}

///|
/// Produce candidate configuration paths in nearest-to-farthest order. This
/// is still lexical; no candidate is read or checked for existence.
pub fn config_candidates(
  target_file : String,
  config_name~ : String = ".editorconfig",
) -> Array[String] {
  let output : Array[String] = []
  for directory in config_search_directories(target_file) {
    output.push(join(directory, config_name))
  }
  output
}

///|
/// Return a path from `base` to `target`, or `None` when their lexical roots
/// differ. Casing in the result is retained from `target`.
pub fn relative_to(
  target : String,
  base : String,
  case : CaseSensitivity,
) -> String? {
  let target_path = parse(target)
  let base_path = parse(base)
  if !roots_equal(target_path.kind, base_path.kind, case) {
    return None
  }
  let common = component_prefix_length(
    target_path.components,
    base_path.components,
    case,
  )
  let output : Array[String] = []
  for index = common; index < base_path.components.length(); index = index + 1 {
    output.push("..")
  }
  for index = common; index < target_path.components.length(); index = index + 1 {
    output.push(target_path.components[index])
  }
  if output.length() == 0 {
    Some(".")
  } else {
    Some(output.join("/"))
  }
}

///|
/// Test whether `target` is equal to or lexically below `directory` using the
/// explicit case strategy. Paths with unlike roots are never within each other.
pub fn is_within(
  target : String,
  directory : String,
  case : CaseSensitivity,
) -> Bool {
  let target_path = parse(target)
  let directory_path = parse(directory)
  roots_equal(target_path.kind, directory_path.kind, case) &&
  directory_path.components.length() <= target_path.components.length() &&
  component_prefix_length(
    target_path.components,
    directory_path.components,
    case,
  ) ==
  directory_path.components.length()
}

///|
pub extend PathKind with Eq::{not_equal, equal}

///|
pub extend PathKind with @debug.Debug::{to_repr}

///|
pub extend CaseSensitivity with Eq::{not_equal, equal}

///|
pub extend CaseSensitivity with @debug.Debug::{to_repr}

///|
pub extend LexicalPath with Eq::{not_equal, equal}

///|
pub extend LexicalPath with @debug.Debug::{to_repr}
