# Contributing

Thanks for helping out. Bug reports and feature requests go through the [issue templates](https://github.com/mhajder/llama.cpp-updater/issues/new/choose). For security problems, follow [SECURITY.md](SECURITY.md) instead.

## Development setup

```sh
git clone https://github.com/mhajder/llama.cpp-updater.git
cd llama.cpp-updater
```

The whole tool is `update-llama.sh`, a single Bash script with no build step. You need [ShellCheck](https://www.shellcheck.net/) and [shfmt](https://github.com/mvdan/sh) to run the same checks as CI, for example `brew install shellcheck shfmt`.

## Before opening a pull request

```sh
shellcheck update-llama.sh
shfmt -d -s -i 4 update-llama.sh
```

`shfmt -w -s -i 4 update-llama.sh` fixes the formatting in place.

- Run the script into a throwaway directory, for example `./update-llama.sh /tmp/llama-test`, and check that the binaries start.
- If you touched the build path, also try `--build-from-source`.
- Mention which OS, architecture and GPU you tested on in the pull request.
- Update the README when you add an option or change behavior.

## Commit messages

Use [Conventional Commits](https://www.conventionalcommits.org/), for example `feat: add a --dry-run option` or `fix: keep symlinks when moving libraries`.

## License

By contributing, you agree that your contributions are licensed under the project's MIT license.
