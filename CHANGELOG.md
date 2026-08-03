# Changelog

All notable changes to this project will be documented in this file. See [conventional commits](https://www.conventionalcommits.org/) for commit guidelines.

- - -
<!-- release -->

## [v0.6.0](https://github.com/tbhb/repotools/compare/1f1e78e755f924112c90f4c7f31838fdf2749df8..v0.6.0) - 2026-08-03

### Features

- (**skills**) hand review-squash-message its inputs up front (#32) - ([19bed45](https://github.com/tbhb/repotools/commit/19bed45bfdf6be19df044a0bb8f9e5c448cd47ab)) - [@tbhb](https://github.com/tbhb)
- (**tools**) report each skill's tool calls and its time on the clock (#30) - ([0c891d4](https://github.com/tbhb/repotools/commit/0c891d414ba61df2dc7858a2767cf891fde068ed)) - [@tbhb](https://github.com/tbhb)

### Bug Fixes

- (**tools**) name the release ref rather than inferring it (#38) - ([d766538](https://github.com/tbhb/repotools/commit/d7665385f0e2dac7dcfeacf676ef805a677c4988)) - [@tbhb](https://github.com/tbhb)
- verify a pinned preset reference at the ref it names (#37) - ([444f921](https://github.com/tbhb/repotools/commit/444f921633380c28a7c2dfabe88fdb35f627f0ff)) - [@tbhb](https://github.com/tbhb)

### Build system

- scope Python coverage from the task instead of a member list (#35) - ([ff44888](https://github.com/tbhb/repotools/commit/ff44888d896d181bfc2af6a2ce5145e42ff6683d)) - [@tbhb](https://github.com/tbhb)
- pre-approve the commit, pr, and merge confirmations per session (#36) - ([6f27794](https://github.com/tbhb/repotools/commit/6f277944a6751a9ab9b5881906afef37d0d2d06a)) - [@tbhb](https://github.com/tbhb)
- install every workspace member and pin what resolves them (#34) - ([1f1e78e](https://github.com/tbhb/repotools/commit/1f1e78e755f924112c90f4c7f31838fdf2749df8)) - [@tbhb](https://github.com/tbhb)

### Continuous Integration

- create the release commit through the API so GitHub signs it (#39) - ([de08aa8](https://github.com/tbhb/repotools/commit/de08aa8615af97b4c9d73e782f3ab56027ace327)) - [@tbhb](https://github.com/tbhb)

- - -

<!-- release -->

## [v0.5.0](https://github.com/tbhb/repotools/compare/2b68005951deb9096af2e59b460b9f366867ae2c..v0.5.0) - 2026-08-03

### Bug Fixes

- use the published vale agent template and read vale's exit status (#26) - ([2b68005](https://github.com/tbhb/repotools/commit/2b68005951deb9096af2e59b460b9f366867ae2c)) - [@tbhb](https://github.com/tbhb)

### Build system

- add the release readiness, dispatch, and verification tasks (#31) - ([044bae4](https://github.com/tbhb/repotools/commit/044bae4070de881ff5fd9c71bd86f5f07042dfa1)) - [@tbhb](https://github.com/tbhb)
- move a consumer between repotools releases with one command (#28) - ([83de50f](https://github.com/tbhb/repotools/commit/83de50fd4f8ffee9f4c2fcca2041febe5b16d6a5)) - [@tbhb](https://github.com/tbhb)
- rewrite every published version literal during a bump (#29) - ([6223b87](https://github.com/tbhb/repotools/commit/6223b87d9fe5754bc9efd4e71296fb277daf4294)) - [@tbhb](https://github.com/tbhb)
- retire the Justfile and run every gate through mise (#27) - ([fa6adbc](https://github.com/tbhb/repotools/commit/fa6adbcf0a64962e7ed8fc08f5a6fd845e5040ed)) - [@tbhb](https://github.com/tbhb)

- - -

<!-- release -->

## [v0.4.0](https://github.com/tbhb/repotools/compare/1e0a27d2bb8020f69e57cf86ab1c7e9353037ad7..v0.4.0) - 2026-08-03

### Bug Fixes

- name the markdown parser when linting a commit message (#24) - ([cab0890](https://github.com/tbhb/repotools/commit/cab0890bfe2a887aabf877a4e44444fe0ddeb13a)) - [@tbhb](https://github.com/tbhb)
- correct the script defects the gates couldn't see (#22) - ([de2c6dd](https://github.com/tbhb/repotools/commit/de2c6ddfb2d2dba527b6c26c59311946d01758a9)) - [@tbhb](https://github.com/tbhb)
- scrub the git environment around the vendored payload sync (#21) - ([634e7f9](https://github.com/tbhb/repotools/commit/634e7f9fac7c21c0238504d0aa7afeecea8f0dde)) - [@tbhb](https://github.com/tbhb)

### Build system

- move the gitleaks pin and task into the shared payload (#23) - ([afd036c](https://github.com/tbhb/repotools/commit/afd036c222be3f8749b8c139afd8d19717439c5c)) - [@tbhb](https://github.com/tbhb)
- lint YAML with ryl in place of yamllint (#20) - ([5515549](https://github.com/tbhb/repotools/commit/55155490865c3ccf2c147f8ed1212eb7719a3858)) - [@tbhb](https://github.com/tbhb)
- pin the apm CLI through mise instead of a curl step (#19) - ([e57f334](https://github.com/tbhb/repotools/commit/e57f334affa3509305c95dca24e91204010335ef)) - [@tbhb](https://github.com/tbhb)

- - -

<!-- release -->

## [v0.3.2](https://github.com/tbhb/repotools/compare/d00af6c7211527f4880e007ff2e96f63987666f6..v0.3.2) - 2026-08-03

### Bug Fixes

- scope the fix-prose guard release to a single edit (#18) - ([9b269d9](https://github.com/tbhb/repotools/commit/9b269d90429a4da30c46e1f8860f79dcf8b47c29)) - [@tbhb](https://github.com/tbhb)
- release the fix-prose lock when its document no longer exists (#16) - ([0811139](https://github.com/tbhb/repotools/commit/0811139c65ecd93d3c45cae0eb4f608382e41d44)) - [@tbhb](https://github.com/tbhb)

### Build system

- package the shared mise tasks and pins as a vendir payload (#17) - ([803bdfe](https://github.com/tbhb/repotools/commit/803bdfea2f0d03a77c41b2a86c97463ff861cbc1)) - [@tbhb](https://github.com/tbhb)
- convert the container-run gates to mise tool pins (#15) - ([5cd9ce1](https://github.com/tbhb/repotools/commit/5cd9ce160e535f817d365b6f30b289f58276066c)) - [@tbhb](https://github.com/tbhb)

### Continuous Integration

- remove the unused setup composites and their Renovate manager (#14) - ([d00af6c](https://github.com/tbhb/repotools/commit/d00af6c7211527f4880e007ff2e96f63987666f6)) - [@tbhb](https://github.com/tbhb)

- - -

<!-- release -->

## [v0.3.1](https://github.com/tbhb/repotools/compare/08897dcadc2db76afb525c7840d2a14564831399..v0.3.1) - 2026-08-02

### Bug Fixes

- sign the release tag in CI and push through the app token (#13) - ([6d7d6e3](https://github.com/tbhb/repotools/commit/6d7d6e3e6917c9a0d016f3f8103518344ef1801e)) - [@tbhb](https://github.com/tbhb)

### Build system

- pin the toolchain with mise from local runs through CI (#12) - ([ec746f3](https://github.com/tbhb/repotools/commit/ec746f30b30a123d63f3a07edbc2a52fcd4d62b5)) - [@tbhb](https://github.com/tbhb)

### Continuous Integration

- permit the mise lock refresh and drop the dead vale rules (#11) - ([08897dc](https://github.com/tbhb/repotools/commit/08897dcadc2db76afb525c7840d2a14564831399)) - [@tbhb](https://github.com/tbhb)

- - -

<!-- release -->

## [v0.3.0](https://github.com/tbhb/repotools/compare/3be10c4ea0eb708758f44f45345b6a90b940ba7d..v0.3.0) - 2026-08-02

### Features

- import the shared workflows, actions, and Renovate presets - ([29ae048](https://github.com/tbhb/repotools/commit/29ae048a69f9079d480fe5a8463592d1137c2723)) - [@tbhb](https://github.com/tbhb)
- import the shared commit-msg hooks from tbhb/pre-commit-hooks - ([c6999ed](https://github.com/tbhb/repotools/commit/c6999edffe6fb59dfb40665174aa9f2605122880)) - [@tbhb](https://github.com/tbhb)
- clear a draft's prose findings in a subagent - ([d7e0da0](https://github.com/tbhb/repotools/commit/d7e0da0e9526728e9438ef00bb3715a5a75b5c61)) - [@tbhb](https://github.com/tbhb)
- apply the corrections vale already wrote - ([2f817fb](https://github.com/tbhb/repotools/commit/2f817fb75fe274349871298455e3efcdc6f97106)) - [@tbhb](https://github.com/tbhb)
- judge a whole draft in one call - ([3478b0e](https://github.com/tbhb/repotools/commit/3478b0e9b219909218b4951beda0ca7aa7a25cb0)) - [@tbhb](https://github.com/tbhb)
- analyze a past session into a retrospective - ([0142bda](https://github.com/tbhb/repotools/commit/0142bdac6461f06829cb41e4e8ad249c97bf456d)) - [@tbhb](https://github.com/tbhb)
- settle a rebase without reading the markers - ([47a3315](https://github.com/tbhb/repotools/commit/47a3315a56c268e97e47279dec82bcfb2ac425c7)) - [@tbhb](https://github.com/tbhb)
- write a squash message from the commits it collapses - ([4fca3d3](https://github.com/tbhb/repotools/commit/4fca3d3ecf438fff4190158da0e84520a6990267)) - [@tbhb](https://github.com/tbhb)
- redeploy APM primitives from a cleared hook state - ([51343b9](https://github.com/tbhb/repotools/commit/51343b9bf585b509a0e88a1aa7740ace322634f2)) - [@tbhb](https://github.com/tbhb)
- ![BREAKING](https://img.shields.io/badge/BREAKING-red) drop the go-lint hook from the package - ([2efb7ce](https://github.com/tbhb/repotools/commit/2efb7ce34f56efd733ee9861433f6f89a0e1bc44)) - [@tbhb](https://github.com/tbhb)
- check a commit against what the index held - ([da96951](https://github.com/tbhb/repotools/commit/da969519a75d8d0585f93f1889639d87ac0a80b5)) - [@tbhb](https://github.com/tbhb)

### Bug Fixes

- hash the vale tree without find -exec - ([427faae](https://github.com/tbhb/repotools/commit/427faaebb432953111486ce93d8d76b73e69c5d8)) - [@tbhb](https://github.com/tbhb)
- give the squash message a vale scope - ([9a50c31](https://github.com/tbhb/repotools/commit/9a50c3114b324b2c284b4e9594e2eae846f01725)) - [@tbhb](https://github.com/tbhb)
- stop the wrap check refusing a GitHub alert - ([e7f7352](https://github.com/tbhb/repotools/commit/e7f735254fc81569c59a28632d427df7c6891c39)) - [@tbhb](https://github.com/tbhb)
- stamp an amend review the caller asked for - ([778790d](https://github.com/tbhb/repotools/commit/778790d94ddfe68f5a47487c8b1324bfa15bf0db)) - [@tbhb](https://github.com/tbhb)
- stop the token count recording what it never measured - ([e5043ab](https://github.com/tbhb/repotools/commit/e5043abf2b419cde5ab71bf521dcb2798a144432)) - [@tbhb](https://github.com/tbhb)
- exempt the generated changelog from the wrap rule - ([69c0821](https://github.com/tbhb/repotools/commit/69c0821d0c14cb9f9a20f3a1d7aa150d11c22097)) - [@tbhb](https://github.com/tbhb)
- let a sibling skill start its own rebase - ([eadde56](https://github.com/tbhb/repotools/commit/eadde562ea4404070c252c21f22d6a8e4e45fc56)) - [@tbhb](https://github.com/tbhb)
- fail a secret scan that walked no commits - ([efa1838](https://github.com/tbhb/repotools/commit/efa1838d9ef29091338bba326ea966c8c661018b)) - [@tbhb](https://github.com/tbhb)
- hold the whitespace gate to files git tracks - ([b5db2f8](https://github.com/tbhb/repotools/commit/b5db2f83624845ea4d78cb06392bfcc33b0d7655)) - [@tbhb](https://github.com/tbhb)
- read the wider script list in the hygiene check - ([63ea838](https://github.com/tbhb/repotools/commit/63ea8382f0cab9955783de6d59d5b81c88ef867d)) - [@tbhb](https://github.com/tbhb)
- leave one way to commit - ([b4d1dd5](https://github.com/tbhb/repotools/commit/b4d1dd5c69c1db504f2eeafe93d716258625878d)) - [@tbhb](https://github.com/tbhb)
- format the scripts git isn't tracking yet - ([09be789](https://github.com/tbhb/repotools/commit/09be789a836c7d58c6cc51d8f1c14126016a7bfb)) - [@tbhb](https://github.com/tbhb)
- restore vocabulary casing checks in Go source - ([78c1a18](https://github.com/tbhb/repotools/commit/78c1a189d9f8fe2378bcc07536a6b78523e278ef)) - [@tbhb](https://github.com/tbhb)
- stand the commit guard down when its work is done - ([15abe71](https://github.com/tbhb/repotools/commit/15abe711eb99e9e619ca61a87620883ed28347cc)) - [@tbhb](https://github.com/tbhb)
- read a cd target the way the shell does - ([2faf047](https://github.com/tbhb/repotools/commit/2faf04724a081b8caaa158043f6b0ac9758c0807)) - [@tbhb](https://github.com/tbhb)
- lint the scripts git isn't tracking yet - ([38896a5](https://github.com/tbhb/repotools/commit/38896a55044eb8c4dc457282596aa1cd5310734e)) - [@tbhb](https://github.com/tbhb)
- stop the vocabulary capitalizing a common noun - ([10666ee](https://github.com/tbhb/repotools/commit/10666eef0b2b1dd61ab39924a4efd4a6f337ef69)) - [@tbhb](https://github.com/tbhb)
- unblock the Windows test arm and the description gate (#5) - ([3be10c4](https://github.com/tbhb/repotools/commit/3be10c4ea0eb708758f44f45345b6a90b940ba7d)) - [@tbhb](https://github.com/tbhb)

### Documentation

- clear the findings the ai-tells bump surfaced - ([c6ea9d6](https://github.com/tbhb/repotools/commit/c6ea9d6eb66d8fcf52a4f3adab708450ff2a08ba)) - [@tbhb](https://github.com/tbhb)
- correct the version the hook bugs were found on - ([723fc4f](https://github.com/tbhb/repotools/commit/723fc4f81d6dd0dc3482d4e2c56ee71f42210c03)) - [@tbhb](https://github.com/tbhb)
- measure a skill before deploying it - ([50e96cf](https://github.com/tbhb/repotools/commit/50e96cf6867376f1b49f3041e1d758c9138bcc62)) - [@tbhb](https://github.com/tbhb)
- put the remaining skill descriptions on one line - ([4ff1596](https://github.com/tbhb/repotools/commit/4ff159639a52656f4f65280251061aa60dd3c8ba)) - [@tbhb](https://github.com/tbhb)

### Build system

- generate a changelog the Markdown gate accepts - ([94cbd75](https://github.com/tbhb/repotools/commit/94cbd751443312a763f13c07d73eb06f16e87fad)) - [@tbhb](https://github.com/tbhb)

### Refactoring

- ![BREAKING](https://img.shields.io/badge/BREAKING-red) rename the APM package to repotools - ([d422df1](https://github.com/tbhb/repotools/commit/d422df1f8576ba63ade2596f64daddc2863353e8)) - [@tbhb](https://github.com/tbhb)
- ![BREAKING](https://img.shields.io/badge/BREAKING-red) rename the Python distribution to repotools - ([9e1e4d8](https://github.com/tbhb/repotools/commit/9e1e4d895084934ec7f134f74d3ec6186f0612ed)) - [@tbhb](https://github.com/tbhb)
- ![BREAKING](https://img.shields.io/badge/BREAKING-red) move the Go module to github.com/tbhb/repotools - ([607c4ad](https://github.com/tbhb/repotools/commit/607c4ade56929d993ddd24efee1cbc040973fb71)) - [@tbhb](https://github.com/tbhb)

- - -

<!-- release -->

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

### Bug Fixes

- stop the skill check passing a file it never read - ([77ebce0](https://github.com/tbhb/agent-tools/commit/77ebce0ca05c90409d68dd69291c1a1d410b5efa)) - [@tbhb](https://github.com/tbhb)
- pin the settings that reshape what an agent reads - ([b020218](https://github.com/tbhb/agent-tools/commit/b020218b81cafb4aaf2465339cf491edb5536cd8)) - [@tbhb](https://github.com/tbhb)
- anchor the commit guard on real invocations - ([e3c14fd](https://github.com/tbhb/agent-tools/commit/e3c14fd1fc889726b409a913c46b519a01248e04)) - [@tbhb](https://github.com/tbhb)
- ![BREAKING](https://img.shields.io/badge/BREAKING-red) rename the Markdown guard off the check prefix - ([b2cf3df](https://github.com/tbhb/agent-tools/commit/b2cf3dffbf5f58caf0fd99e9dfbe0cdf850f3db3)) - [@tbhb](https://github.com/tbhb)
- create the cosmic-ray session directory before init - ([782a761](https://github.com/tbhb/agent-tools/commit/782a761f57da7e0892797b9d0962c740c0b55a38)) - [@tbhb](https://github.com/tbhb)
- point the Python fuzz sweep at the real property tests - ([7441bfa](https://github.com/tbhb/agent-tools/commit/7441bfac68954069bf4b3b2954d085ac6397a4d9)) - [@tbhb](https://github.com/tbhb)

### Documentation

- point the Python comments at packages/ - ([ea2cefd](https://github.com/tbhb/agent-tools/commit/ea2cefdfd66c5d8b7b0318a1f995a1b6a83e5a70)) - [@tbhb](https://github.com/tbhb)
- describe the Python toolchain and the recipe naming - ([40794bf](https://github.com/tbhb/agent-tools/commit/40794bfa9edc5fdca595ad370cbd86812915b417)) - [@tbhb](https://github.com/tbhb)

### Build system

- aim the Python mutation sweep at the workspace packages - ([02dd6b3](https://github.com/tbhb/agent-tools/commit/02dd6b3f25ca1d4ae04c34f180626950b19e182e)) - [@tbhb](https://github.com/tbhb)
- gate Python on the pre-commit stage - ([16277a9](https://github.com/tbhb/agent-tools/commit/16277a90a1f084cce8316f4ddb8b7e51d8826bb4)) - [@tbhb](https://github.com/tbhb)
- add the Python recipe surface - ([e037845](https://github.com/tbhb/agent-tools/commit/e03784550a1e64ec125ea55603d56f94347e8986)) - [@tbhb](https://github.com/tbhb)
- suffix the Go recipes with -go - ([22ac113](https://github.com/tbhb/agent-tools/commit/22ac113947e3708e087430335628f0e7a53ba1ac)) - [@tbhb](https://github.com/tbhb)
- add the Python toolchain on a uv workspace - ([09a2329](https://github.com/tbhb/agent-tools/commit/09a23296d5526ada3a4678d5152dfae05022a26d)) - [@tbhb](https://github.com/tbhb)

- - -

<!-- release -->

## [v0.1.1](https://github.com/tbhb/agent-tools/compare/b0b1c9f71068f0920ab239d42681f2af34f345a9..v0.1.1) - 2026-08-01

### Documentation

- stop hard-wrapping the markdown prose (#4) - ([6f75183](https://github.com/tbhb/agent-tools/commit/6f75183cda5663100cdc9737970b5b8ca8c21a0f)) - [@tbhb](https://github.com/tbhb)

### Continuous Integration

- source the commit-msg gates from the tbhb hook repo (#1) - ([b0b1c9f](https://github.com/tbhb/agent-tools/commit/b0b1c9f71068f0920ab239d42681f2af34f345a9)) - [@tbhb](https://github.com/tbhb)

- - -

<!-- release -->

## [v0.1.0](https://github.com/tbhb/agent-tools/compare/049e81a012a34887cd44a1a256cdfbd5656de6d0..v0.1.0) - 2026-08-01

### Features

- publish the agent primitives as an apm package - ([aab294e](https://github.com/tbhb/agent-tools/commit/aab294e22a54ac108f6325657669e86f84946e0f)) - [@tbhb](https://github.com/tbhb)
- add the agent CLIs as a vendored Go module - ([1136ae6](https://github.com/tbhb/agent-tools/commit/1136ae65ad62993885fc003a7d689497d547c539)) - [@tbhb](https://github.com/tbhb)

### Documentation

- explain the tools and route review - ([cacbd52](https://github.com/tbhb/agent-tools/commit/cacbd52b9f2cf9e09b2a660cb08c067b69287174)) - [@tbhb](https://github.com/tbhb)

### Build system

- put just in front of the whole toolchain - ([0e43e85](https://github.com/tbhb/agent-tools/commit/0e43e854e86dae7af53f147b65c0522e03af09aa)) - [@tbhb](https://github.com/tbhb)

### Continuous Integration

- run the gates and the scanners on GitHub Actions - ([42f6a6a](https://github.com/tbhb/agent-tools/commit/42f6a6a7e6b2b7e944f5d3a7f908a500a827d2ae)) - [@tbhb](https://github.com/tbhb)
