// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "yino04/moon-editorconfig"

version = "0.1.0"

readme = "README.md"

repository = "https://github.com/yino04/moon-editorconfig"

license = "Apache-2.0"

keywords = [ "editorconfig", "parser", "glob", "configuration" ]

preferred_target = "native"

description = "EditorConfig core parser, bounded glob matcher, and configuration resolver"

import {
  "moonbitlang/async@0.22.5",
}
