# Contributing

Thanks for helping out. Bug reports and feature requests go through the [issue templates](https://github.com/mhajder/llama.cpp-updater/issues/new/choose). For security problems, follow [SECURITY.md](SECURITY.md) instead.

## Development setup

```sh
git clone https://github.com/mhajder/llama.cpp-updater.git
cd llama.cpp-updater
```

The whole tool is `update-llama.sh`, a single Bash script with no build step. The checks are run by [prek](https://github.com/j178/prek), a faster drop-in for pre-commit; install it with `brew install prek`, `uv tool install prek` or `pipx install prek`. prek downloads the tools the hooks need (ShellCheck, shfmt, typos, commitizen) itself.

`prek install` (run it once in the clone) sets up the git hooks, configured in [`.pre-commit-config.yaml`](.pre-commit-config.yaml):

- **on commit**: ShellCheck, shfmt (`-i 4 -s`), typos and basic file checks (trailing whitespace, line endings, YAML, executable bits, large files, private keys)
- **on the commit message**: commitizen checks it follows Conventional Commits
- **on push**: commitizen checks every commit being pushed; shfmt, typos and some of the file checks run again on the changed files

CI runs the commit hooks on every push and pull request; the commit message checks only run locally.

## Before opening a pull request

```sh
prek run --all-files
```

Hooks that fix files (shfmt, trailing whitespace, line endings, end of file) change them in place; review and stage the changes, then run it again.

- Run the script into a throwaway directory, for example `./update-llama.sh /tmp/llama-test`, and check that the binaries start.
- If you touched the build path, also try `--build-from-source`.
- If you touched `--restart-cmd` or `--wait-idle`, test against a running `llama-server`, with and without `--metrics`, and in router mode if you can.
- Mention which OS, architecture and GPU you tested on in the pull request.
- Update the README when you add an option or change behavior.

## Commit messages

Use [Conventional Commits](https://www.conventionalcommits.org/), for example `feat: add a --dry-run option` or `fix: keep symlinks when moving libraries`. The commit-msg hook rejects other formats.

## License

By contributing, you agree that your contributions are licensed under the project's MIT license.
