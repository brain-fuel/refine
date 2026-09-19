# ECMA-262 regex guest notices

The checked WebAssembly artifact links modified QuickJS-NG 0.15.1, embeds the
fixed CommonJS distribution of `@eslint-community/regexpp` 4.12.2, and links
runtime objects supplied by wasi-sdk 33. Exact revisions and hashes are in
`manifest.json`; the Refine-specific source and QuickJS interrupt patch are in
this directory.

QuickJS-NG and regexpp are distributed under the MIT license. wasi-sdk is
Apache-2.0; its wasi-libc and LLVM/compiler-rt components contain code under
the accompanying MIT, Apache-2.0, and Apache-2.0 WITH LLVM-exception texts.
Those texts are retained in `licenses/`.

The guest has no WASI import. `no_capabilities.c` resolves libc's otherwise
unused clock, random, and file-descriptor symbols inside the module with fixed
or failing implementations. Its sole host import is the interrupt callback
listed in the manifest.
