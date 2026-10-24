# MoonEditorConfig

MoonEditorConfig is a MoonBit implementation of the EditorConfig core: it parses
`.editorconfig` files, compiles and evaluates EditorConfig globs, resolves
directory inheritance, validates standard properties, and explains where each
effective value came from.

The project targets [EditorConfig specification 0.17.2](https://spec.editorconfig.org/).
It is an independent implementation informed by the specification and by
behavioral comparison with [ec4j](https://github.com/ec4j/ec4j); it is not a
formatter and does not edit source files.

## Status

Development is in progress. The public API, CLI, compatibility matrix, tests,
and release instructions will be documented as each verified milestone lands.
No Mooncakes package has been published yet.

## Development

Install the current MoonBit toolchain, then run:

```text
moon check --target js --deny-warn
moon test --target js --deny-warn
moon fmt --check
```

See `docs/COMPATIBILITY.md` for the supported specification surface and
`docs/UPSTREAM.md` for pinned reference revisions and licensing notes.

## License

Apache-2.0. See `LICENSE` and `NOTICE`.
