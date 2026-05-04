# Changelog

## [0.8.1](https://github.com/git-extensions/git-ai/compare/v0.8.0...v0.8.1) (2026-05-04)


### Bug Fixes

* **github:** correct action versions in update.yml ([b42d2a5](https://github.com/git-extensions/git-ai/commit/b42d2a5cd3b6d6a3e7f496c805b4c555b7d5e8fe))

## [0.8.0](https://github.com/git-extensions/git-ai/compare/v0.7.1...v0.8.0) (2026-05-03)


### Features

* **gemini:** add support for Gemini CLI agent ([c1cc878](https://github.com/git-extensions/git-ai/commit/c1cc8780c3e8310e42d62e7f085e655cecada915))
* **gemini:** parse json output with jq ([12bd875](https://github.com/git-extensions/git-ai/commit/12bd875f16e21d45e0cdc1940da3fcb248ede7a8))
* **nix:** integrate llm-agents.nix flake ([d3aae2d](https://github.com/git-extensions/git-ai/commit/d3aae2d7482c9b421030a5907bee9d8c2dc12060))
* support codex as an ai agent ([a419dab](https://github.com/git-extensions/git-ai/commit/a419dab3f2585082335de9bc3f20702e4ea3db0d))

## [0.7.1](https://github.com/git-extensions/git-ai/compare/v0.7.0...v0.7.1) (2026-04-16)


### Bug Fixes

* add postCreateCommand to restore nix volume permissions ([acf78aa](https://github.com/git-extensions/git-ai/commit/acf78aab669537b7b94b1aad90480d79088dca86))

## [0.7.0](https://github.com/git-extensions/git-ai/compare/v0.6.0...v0.7.0) (2026-03-20)


### Features

* remove mandatory -- separator for git commit passthrough ([30cffdc](https://github.com/git-extensions/git-ai/commit/30cffdc4b57892721db0094903eefd3445a94d69))


### Reverts

* restore gum as a required dependency ([2cf29c1](https://github.com/git-extensions/git-ai/commit/2cf29c1b0a74e138d6f0d5287dd6d990f5dd9c66))

## [0.6.0](https://github.com/git-extensions/git-ai/compare/v0.5.0...v0.6.0) (2026-03-18)


### Features

* make gum optional with plain stderr fallback ([00808d0](https://github.com/git-extensions/git-ai/commit/00808d00cd8fde98f02b313cce3289de3489c6ce))

## [0.5.0](https://github.com/git-extensions/git-ai/compare/v0.4.0...v0.5.0) (2026-03-08)


### Features

* add zsh plugin ([3a474b4](https://github.com/git-extensions/git-ai/commit/3a474b44c807842382baa84b21e48f4ebe1351f5))
* add zsh plugin and update installation docs ([d9e5879](https://github.com/git-extensions/git-ai/commit/d9e5879e7905524c23fbc7d98be004b4ca2e2745))

## [0.4.0](https://github.com/git-extensions/git-ai/compare/v0.3.0...v0.4.0) (2026-03-07)


### Features

* use share/ layout and makeWrapper with gum as runtime dep ([548faf7](https://github.com/git-extensions/git-ai/commit/548faf728384f8259a0367c99d3b01c5895c46d9))


### Bug Fixes

* handle first commit in empty repo gracefully ([50a823d](https://github.com/git-extensions/git-ai/commit/50a823d910e034a8d37427424fd96617cb0d0d70))
* strip trailing newline from version.txt in flake ([f5cc8ad](https://github.com/git-extensions/git-ai/commit/f5cc8adf31b7dcb15b52635897653c2199688bf0))

## [0.3.0](https://github.com/git-extensions/git-ai/compare/v0.2.0...v0.3.0) (2026-03-07)


### Features

* add packages.default derivation ([0e8b9f9](https://github.com/git-extensions/git-ai/commit/0e8b9f9eafab9473dbc61e401163b80dfb4a2b80))

## [0.2.0](https://github.com/git-extensions/git-ai/compare/v0.1.0...v0.2.0) (2026-02-28)


### Features

* add git-ai CLI for AI-powered commit message generation ([bd3f53a](https://github.com/git-extensions/git-ai/commit/bd3f53ad44188b5bdbfd7b8dea3de11728ddd3f9))
* add git-ai CLI for AI-powered commit message generation ([f014454](https://github.com/git-extensions/git-ai/commit/f014454bf5d4252db013b27597cf8252b55d89ed))
