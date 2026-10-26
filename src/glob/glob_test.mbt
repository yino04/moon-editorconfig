///|
fn compiled(pattern : String) -> @glob.CompiledGlob raise {
  let result = @glob.compile_glob(pattern)
  guard result.glob is Some(value) else {
    fail("expected glob to compile: \{pattern}")
  }
  value
}

///|
fn assert_glob(pattern : String, path : String, expected : Bool) -> Unit raise {
  let actual = @glob.glob_matches(compiled(pattern), path)
  assert_eq(actual, expected)
}

///|
test "literal matching is exact and case-sensitive" {
  assert_glob("README.md", "README.md", true)
  assert_glob("README.md", "readme.md", false)
  assert_glob("README.md", "README.mdx", false)
}

///|
test "single star accepts zero or many non-separator characters" {
  assert_glob("a*e.c", "ae.c", true)
  assert_glob("a*e.c", "ace.c", true)
  assert_glob("a*e.c", "abcde.c", true)
  assert_glob("a*e.c", "a/e.c", false)
}

///|
test "single star includes dot files" {
  assert_glob("*", ".editorconfig", true)
  assert_glob("Bar/*", "Bar/.editorconfig", true)
}

///|
test "question consumes one character but never a slash" {
  assert_glob("som?.c", "some.c", true)
  assert_glob("som?.c", "som.c", false)
  assert_glob("som?.c", "som/.c", false)
  assert_glob("?.txt", "中.txt", true)
}

///|
test "globstar crosses arbitrary directory separators" {
  assert_glob("a**z.c", "az.c", true)
  assert_glob("a**z.c", "amnz.c", true)
  assert_glob("a**z.c", "a/mn/z.c", true)
}

///|
test "globstar after a slash remains attached to that prefix" {
  assert_glob("b/**z.c", "b/z.c", true)
  assert_glob("b/**z.c", "b/mnz.c", true)
  assert_glob("b/**z.c", "b/mn/z.c", true)
  assert_glob("b/**z.c", "bmnz.c", false)
}

///|
test "non-segment globstar before slash preserves the slash" {
  assert_glob("c**/z.c", "c/z.c", true)
  assert_glob("c**/z.c", "cmn/z.c", true)
  assert_glob("c**/z.c", "c/mn/z.c", true)
  assert_glob("c**/z.c", "cmnz.c", false)
  assert_glob("c**/z.c", "c/mnz.c", false)
}

///|
test "segment globstar slash matches zero or many directories" {
  assert_glob("d/**/z.c", "d/z.c", true)
  assert_glob("d/**/z.c", "d/mn/z.c", true)
  assert_glob("d/**/z.c", "d/a/b/c/z.c", true)
  assert_glob("d/**/z.c", "dmn/z.c", false)
  assert_glob("src/**/*.mbt", "src/main.mbt", true)
  assert_glob("src/**/*.mbt", "src/deep/test.mbt", true)
}

///|
test "character class choices and negation" {
  assert_glob("[ab].a", "a.a", true)
  assert_glob("[ab].a", "c.a", false)
  assert_glob("[!ab].b", "c.b", true)
  assert_glob("[!ab].b", "a.b", false)
}

///|
test "character class ranges are inclusive" {
  assert_glob("[d-g].c", "d.c", true)
  assert_glob("[d-g].c", "f.c", true)
  assert_glob("[d-g].c", "g.c", true)
  assert_glob("[d-g].c", "h.c", false)
  assert_glob("[!d-g].d", "h.d", true)
  assert_glob("[!d-g].d", "f.d", false)
}

///|
test "class ranges can be mixed with literal choices" {
  assert_glob("[abd-g].e", "a.e", true)
  assert_glob("[abd-g].e", "e.e", true)
  assert_glob("[abd-g].e", "z.e", false)
}

///|
test "dash at a class edge is literal" {
  assert_glob("[-ab].f", "-.f", true)
  assert_glob("[-ab].f", "a.f", true)
  assert_glob("[ab-].f", "-.f", true)
}

///|
test "escaped closing bracket stays inside its class" {
  assert_glob("[\\]ab].g", "].g", true)
  assert_glob("[\\]ab].g", "a.g", true)
  assert_glob("[!\\]ab].g", "c.g", true)
  assert_glob("[!\\]ab].g", "].g", false)
}

///|
test "slash inside a class is matchable but does not anchor the glob" {
  assert_glob("ab[e/]cd.i", "ab/cd.i", true)
  assert_glob("ab[e/]cd.i", "deep/abecd.i", true)
  assert_glob("ab[e/]cd.i", "abxcd.i", false)
}

///|
test "an unclosed class opener is literal" {
  assert_glob("ab[/c", "ab[/c", true)
  assert_glob("ab[/c", "ab/c", false)
}

///|
test "word alternatives choose one complete branch" {
  assert_glob("*.{py,js,html}", "test.py", true)
  assert_glob("*.{py,js,html}", "test.js", true)
  assert_glob("*.{py,js,html}", "test.html", true)
  assert_glob("*.{py,js,html}", "test.pyc", false)
}

///|
test "nested alternatives preserve nested branch boundaries" {
  assert_glob("{word,{also},this}.g", "word.g", true)
  assert_glob("{word,{also},this}.g", "{also}.g", true)
  assert_glob("{word,{also},this}.g", "this.g", true)
  assert_glob("{word,{also},this}.g", "also.g", false)
  assert_glob("{{a,b},c}.k", "a.k", true)
  assert_glob("{{a,b},c}.k", "b.k", true)
  assert_glob("{{a,b},c}.k", "c.k", true)
}

///|
test "empty branches are valid when a brace has commas" {
  assert_glob("a{b,c,}.d", "a.d", true)
  assert_glob("a{b,c,}.d", "ab.d", true)
  assert_glob("a{b,c,}.d", "ac.d", true)
  assert_glob("a{,b,,c,}.e", "a.e", true)
  assert_glob("a{,b,,c,}.e", "ab.e", true)
  assert_glob("a{,b,,c,}.e", "ac.e", true)
}

///|
test "singleton and empty braces are literal" {
  assert_glob("{single}.b", "{single}.b", true)
  assert_glob("{single}.b", "single.b", false)
  assert_glob("{}.c", "{}.c", true)
  assert_glob("{}.c", ".c", false)
}

///|
test "a separator inside literal singleton braces still anchors the glob" {
  let value = compiled("{foo/bar}")
  assert_true(value.anchored)
  assert_glob("{foo/bar}", "{foo/bar}", true)
  assert_glob("{foo/bar}", "deep/{foo/bar}", false)
}

///|
test "unclosed braces retain literal spelling" {
  assert_glob("{.f", "{.f", true)
  assert_glob("{{,b,c{d}.i", "{{,b,c{d}.i", true)
  assert_glob("{{,b,c{d}.i", "b.i", false)
}

///|
test "escaped brace punctuation does not split choices" {
  assert_glob("{a\\,b,cd}.txt", "a,b.txt", true)
  assert_glob("{a\\,b,cd}.txt", "a.txt", false)
  assert_glob("{e,\\},f}.txt", "}.txt", true)
  assert_glob("{g,\\\\,i}.txt", "\\.txt", true)
}

///|
test "wildcards and classes are active inside alternatives" {
  let pattern = "{some,a{*c,b}[ef]}.j"
  assert_glob(pattern, "some.j", true)
  assert_glob(pattern, "abe.j", true)
  assert_glob(pattern, "acf.j", true)
  assert_glob(pattern, "abcg.j", false)
  assert_glob(pattern, "ae.j", false)
}

///|
test "ascending integer range includes both endpoints" {
  assert_glob("file{3..120}.txt", "file3.txt", true)
  assert_glob("file{3..120}.txt", "file15.txt", true)
  assert_glob("file{3..120}.txt", "file120.txt", true)
  assert_glob("file{3..120}.txt", "file2.txt", false)
  assert_glob("file{3..120}.txt", "file121.txt", false)
  assert_glob("file{3..120}.txt", "file5a.txt", false)
}

///|
test "numeric range candidates use canonical decimal spelling" {
  assert_glob("{3..120}", "60", true)
  assert_glob("{3..120}", "060", false)
  assert_glob("{03..5}", "3", true)
  assert_glob("{03..5}", "03", false)
}

///|
test "signed numeric ranges cross zero" {
  assert_glob("v{-2..2}", "v-2", true)
  assert_glob("v{-2..2}", "v-1", true)
  assert_glob("v{-2..2}", "v0", true)
  assert_glob("v{-2..2}", "v2", true)
  assert_glob("v{-2..2}", "v-3", false)
  assert_glob("v{-2..2}", "v+1", false)
}

///|
test "descending equal and alphabetical double-dot braces are literal" {
  assert_glob("{3..1}", "{3..1}", true)
  assert_glob("{3..1}", "2", false)
  assert_glob("{4..4}", "{4..4}", true)
  assert_glob("{aardvark..antelope}", "{aardvark..antelope}", true)
  assert_glob("{aardvark..antelope}", "agreement", false)
}

///|
test "a path separator anchors the glob at the config directory" {
  assert_glob("src/*.mbt", "src/main.mbt", true)
  assert_glob("src/*.mbt", "src/deep/test.mbt", false)
  assert_glob("src/*.mbt", "other/src/main.mbt", false)
}

///|
test "a glob without separator matches a basename at any depth" {
  assert_glob("*.mbt", "main.mbt", true)
  assert_glob("*.mbt", "src/main.mbt", true)
  assert_glob("*.mbt", "src/deep/main.mbt", true)
  assert_glob("*.mbt", "src/main.md", false)
}

///|
test "leading slash is irrelevant for a relative anchored glob" {
  assert_glob("/test1/file.{java,js,rb}", "test1/file.java", true)
  assert_glob("/test1/file.{java,js,rb}", "other/test1/file.java", false)
}

///|
test "a section glob ending in slash never matches a file" {
  let value = compiled("src/**/")
  assert_true(value.never_matches_file)
  assert_false(@glob.glob_matches(value, "src/"))
  assert_false(@glob.glob_matches(value, "src/deep/"))
}

///|
test "backslash escapes metacharacters rather than separating paths" {
  assert_glob("literal\\*.txt", "literal*.txt", true)
  assert_glob("literal\\*.txt", "literal-file.txt", false)
  assert_glob("what\\?.txt", "what?.txt", true)
  assert_glob("what\\?.txt", "whata.txt", false)
  assert_glob("dir\\*.txt", "dir\\name.txt", false)
}

///|
test "UTF-8 literals and wildcard characters are scalar-aware" {
  assert_glob("中文.txt", "中文.txt", true)
  assert_glob("中?.txt", "中文.txt", true)
  assert_glob("中?.txt", "中ab.txt", false)
  assert_glob("😀?.txt", "😀好.txt", true)
}

///|
test "compiled representation exposes explicit AST nodes" {
  let value = compiled("src/**/[a-c]?.{mbt,md}")
  assert_true(value.anchored)
  assert_true(value.ast.atoms.length() >= 7)
  assert_true(value.ast.atoms[0] is @glob.Literal('s'))
  assert_true(value.ast.atoms[3] is @glob.Separator)
  assert_true(value.ast.atoms[4] is @glob.RecursiveDirectories)
  assert_eq(value.alternative_count, 2)
}

///|
test "maximum glob length is enforced before parsing" {
  let base = @model.default_limits()
  let limits = { ..base, max_glob_length: 4, }
  let result = @glob.compile_glob("12345", limits~)
  assert_false(result.is_ok())
  assert_true(result.glob is None)
  assert_eq(result.diagnostics[0].code, "E_GLOB_LENGTH")
}

///|
test "glob length counts Unicode scalar values at the boundary" {
  let limits = { ..@model.default_limits(), max_glob_length: 2, }
  let accepted = @glob.compile_glob("😀?", limits~)
  guard accepted.glob is Some(value) else { fail("two characters must fit") }
  assert_true(@glob.match_glob(value, "😀x").matched)
  let rejected = @glob.compile_glob("😀?x", limits~)
  assert_true(rejected.glob is None)
  assert_eq(rejected.diagnostics[0].code, "E_GLOB_LENGTH")
}

///|
test "maximum brace nesting is enforced" {
  let base = @model.default_limits()
  let limits = { ..base, max_glob_nesting: 1, }
  let result = @glob.compile_glob("{a,{b,c}}", limits~)
  assert_false(result.is_ok())
  assert_eq(result.diagnostics[0].code, "E_GLOB_NESTING_LIMIT")
}

///|
test "numeric ranges participate in the nesting limit" {
  let base = @model.default_limits()
  let limits = { ..base, max_glob_nesting: 1, }
  let result = @glob.compile_glob("{a,{1..3}}", limits~)
  assert_false(result.is_ok())
  assert_eq(result.diagnostics[0].code, "E_GLOB_NESTING_LIMIT")
}

///|
test "maximum alternative count includes empty branches" {
  let base = @model.default_limits()
  let limits = { ..base, max_alternatives: 3, }
  let result = @glob.compile_glob("{a,,b,c}", limits~)
  assert_false(result.is_ok())
  assert_eq(result.diagnostics[0].code, "E_GLOB_ALTERNATIVE_LIMIT")
}

///|
test "maximum numeric range cardinality is enforced" {
  let base = @model.default_limits()
  let limits = { ..base, max_range_cardinality: 3, }
  let result = @glob.compile_glob("{1..4}", limits~)
  assert_false(result.is_ok())
  assert_eq(result.diagnostics[0].code, "E_GLOB_RANGE_LIMIT")
}

///|
test "combined numeric ranges share the cardinality budget" {
  let base = @model.default_limits()
  let limits = { ..base, max_range_cardinality: 5, }
  let result = @glob.compile_glob("{1..3}{7..9}", limits~)
  assert_false(result.is_ok())
  assert_eq(result.diagnostics[0].code, "E_GLOB_RANGE_LIMIT")
}

///|
test "match operation exhaustion is observable and bounded" {
  let base = @model.default_limits()
  let limits = { ..base, max_match_operations: 8, }
  let compile_result = @glob.compile_glob("**needle", limits~)
  guard compile_result.glob is Some(value) else { fail("expected compile") }
  let result = @glob.match_glob(value, "a/b/c/d/e/needle")
  assert_false(result.matched)
  assert_true(result.exhausted)
  assert_eq(result.operations, 8)
  assert_eq(result.diagnostics[0].code, "E_GLOB_MATCH_LIMIT")
}

///|
test "invalid zero-valued work budget is rejected" {
  let base = @model.default_limits()
  let limits = { ..base, max_match_operations: 0, }
  let result = @glob.compile_glob("*.mbt", limits~)
  assert_false(result.is_ok())
  assert_eq(result.diagnostics[0].code, "E_GLOB_LIMITS")
}

///|
test "long adversarial star input terminates under the configured budget" {
  let base = @model.default_limits()
  let limits = { ..base, max_match_operations: 2000, }
  let compile_result = @glob.compile_glob("*a*a*a*a*a*a*a*a*b", limits~)
  guard compile_result.glob is Some(value) else { fail("expected compile") }
  let candidate = "a".repeat(600)
  let result = @glob.match_glob(value, candidate)
  assert_true(result.exhausted || !result.matched)
  assert_true(result.operations <= 2000)
}
