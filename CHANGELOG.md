# Changelog

All notable changes to this project will be documented in this file. See [conventional commits](https://www.conventionalcommits.org/) for commit guidelines.

- - -

## [v0.2.0](https://github.com/tbhb/agent-tools/compare/ef1a589925a9fa434c9867021ddc76da9766b69e..v0.2.0) - 2026-08-02

### Features

- let a fix land as an amend - ([8d4029b](https://github.com/tbhb/agent-tools/commit/8d4029b1c1c8f060605f0a8668e4c2978c84a680)) - [@tbhb](https://github.com/tbhb)
- draft pull request descriptions in a forked agent - ([871086a](https://github.com/tbhb/agent-tools/commit/871086a8ba8c5389510a708ee082fa6f803f07ff)) - [@tbhb](https://github.com/tbhb)
- run pull requests through a reviewed workflow - ([1cfa984](https://github.com/tbhb/agent-tools/commit/1cfa984c6e7a135cded45b90ab2e139d1f6457e6)) - [@tbhb](https://github.com/tbhb)
- measure what a skill costs to carry - ([b8c33db](https://github.com/tbhb/agent-tools/commit/b8c33db393f37222e40acf1aac938e776a0a7d9c)) - [@tbhb](https://github.com/tbhb)
- wire check-markdown into every gate that runs it - ([ffb6307](https://github.com/tbhb/agent-tools/commit/ffb630727374b68fe0d91b703190e070a98e99c5)) - [@tbhb](https://github.com/tbhb)
- add check-markdown for one-line Markdown paragraphs - ([714bdf8](https://github.com/tbhb/agent-tools/commit/714bdf82fafd7b492dbf6e79e6190d20f77b4114)) - [@tbhb](https://github.com/tbhb)
- register the go-lint hook as an apm primitive - ([c60e9da](https://github.com/tbhb/agent-tools/commit/c60e9da318380026668f8addb3f2879eb134a9ea)) - [@tbhb](https://github.com/tbhb)
- gate agent commits behind review and a guard - ([ef1a589](https://github.com/tbhb/agent-tools/commit/ef1a589925a9fa434c9867021ddc76da9766b69e)) - [@tbhb](https://github.com/tbhb)

#### Bug Fixes

- stop the skill check passing a file it never read - ([77ebce0](https://github.com/tbhb/agent-tools/commit/77ebce0ca05c90409d68dd69291c1a1d410b5efa)) - [@tbhb](https://github.com/tbhb)
- pin the settings that reshape what an agent reads - ([b020218](https://github.com/tbhb/agent-tools/commit/b020218b81cafb4aaf2465339cf491edb5536cd8)) - [@tbhb](https://github.com/tbhb)
- anchor the commit guard on real invocations - ([e3c14fd](https://github.com/tbhb/agent-tools/commit/e3c14fd1fc889726b409a913c46b519a01248e04)) - [@tbhb](https://github.com/tbhb)
- ![BREAKING](https://img.shields.io/badge/BREAKING-red) rename the Markdown guard off the check prefix - ([b2cf3df](https://github.com/tbhb/agent-tools/commit/b2cf3dffbf5f58caf0fd99e9dfbe0cdf850f3db3)) - [@tbhb](https://github.com/tbhb)
- create the cosmic-ray session directory before init - ([782a761](https://github.com/tbhb/agent-tools/commit/782a761f57da7e0892797b9d0962c740c0b55a38)) - [@tbhb](https://github.com/tbhb)
- point the Python fuzz sweep at the real property tests - ([7441bfa](https://github.com/tbhb/agent-tools/commit/7441bfac68954069bf4b3b2954d085ac6397a4d9)) - [@tbhb](https://github.com/tbhb)

#### Documentation

- point the Python comments at packages/ - ([ea2cefd](https://github.com/tbhb/agent-tools/commit/ea2cefdfd66c5d8b7b0318a1f995a1b6a83e5a70)) - [@tbhb](https://github.com/tbhb)
- describe the Python toolchain and the recipe naming - ([40794bf](https://github.com/tbhb/agent-tools/commit/40794bfa9edc5fdca595ad370cbd86812915b417)) - [@tbhb](https://github.com/tbhb)

#### Build system

- aim the Python mutation sweep at the workspace packages - ([02dd6b3](https://github.com/tbhb/agent-tools/commit/02dd6b3f25ca1d4ae04c34f180626950b19e182e)) - [@tbhb](https://github.com/tbhb)
- gate Python on the pre-commit stage - ([16277a9](https://github.com/tbhb/agent-tools/commit/16277a90a1f084cce8316f4ddb8b7e51d8826bb4)) - [@tbhb](https://github.com/tbhb)
- add the Python recipe surface - ([e037845](https://github.com/tbhb/agent-tools/commit/e03784550a1e64ec125ea55603d56f94347e8986)) - [@tbhb](https://github.com/tbhb)
- suffix the Go recipes with -go - ([22ac113](https://github.com/tbhb/agent-tools/commit/22ac113947e3708e087430335628f0e7a53ba1ac)) - [@tbhb](https://github.com/tbhb)
- add the Python toolchain on a uv workspace - ([09a2329](https://github.com/tbhb/agent-tools/commit/09a23296d5526ada3a4678d5152dfae05022a26d)) - [@tbhb](https://github.com/tbhb)

- - -

## [v0.1.1](https://github.com/tbhb/agent-tools/compare/b0b1c9f71068f0920ab239d42681f2af34f345a9..v0.1.1) - 2026-08-01

### Documentation

- stop hard-wrapping the markdown prose (#4) - ([6f75183](https://github.com/tbhb/agent-tools/commit/6f75183cda5663100cdc9737970b5b8ca8c21a0f)) - [@tbhb](https://github.com/tbhb)

#### Continuous Integration

- source the commit-msg gates from the tbhb hook repo (#1) - ([b0b1c9f](https://github.com/tbhb/agent-tools/commit/b0b1c9f71068f0920ab239d42681f2af34f345a9)) - [@tbhb](https://github.com/tbhb)

- - -

## [v0.1.0](https://github.com/tbhb/agent-tools/compare/049e81a012a34887cd44a1a256cdfbd5656de6d0..v0.1.0) - 2026-08-01

### Features

- publish the agent primitives as an apm package - ([aab294e](https://github.com/tbhb/agent-tools/commit/aab294e22a54ac108f6325657669e86f84946e0f)) - [@tbhb](https://github.com/tbhb)
- add the agent CLIs as a vendored Go module - ([1136ae6](https://github.com/tbhb/agent-tools/commit/1136ae65ad62993885fc003a7d689497d547c539)) - [@tbhb](https://github.com/tbhb)

#### Documentation

- explain the tools and route review - ([cacbd52](https://github.com/tbhb/agent-tools/commit/cacbd52b9f2cf9e09b2a660cb08c067b69287174)) - [@tbhb](https://github.com/tbhb)

#### Build system

- put just in front of the whole toolchain - ([0e43e85](https://github.com/tbhb/agent-tools/commit/0e43e854e86dae7af53f147b65c0522e03af09aa)) - [@tbhb](https://github.com/tbhb)

#### Continuous Integration

- run the gates and the scanners on GitHub Actions - ([42f6a6a](https://github.com/tbhb/agent-tools/commit/42f6a6a7e6b2b7e944f5d3a7f908a500a827d2ae)) - [@tbhb](https://github.com/tbhb)
