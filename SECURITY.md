# Security Policy

## Supported versions

Only the current `main` branch gets security fixes. Download the latest `update-llama.sh` and check that the issue still happens before reporting.

## Reporting a vulnerability

Please do not open a public issue. Report it privately through [GitHub private vulnerability reporting](https://github.com/mhajder/llama.cpp-updater/security/advisories/new).

Include the OS and architecture, the exact command you ran, how to reproduce it and what an attacker could do with it.

I aim to acknowledge a report within 7 days and will keep you updated until it is fixed.

## Scope

In scope is `update-llama.sh`, for example:

- deleting or overwriting files outside the target directory, or files the script did not install
- an archive entry or symlink that makes extraction write outside the target directory
- release names, tag names or paths reaching a shell command in a way that runs code
- downloading from anywhere other than the `ggml-org/llama.cpp` GitHub releases, or over plain HTTP
- `GITHUB_TOKEN`/`GH_TOKEN` or `LLAMA_API_KEY` appearing on a command line (visible in `ps`), in output or in a file other users can read, or being sent anywhere other than `api.github.com` and the `--wait-idle` URL respectively
- a response from the `--wait-idle` server (model names, metrics, JSON) reaching a shell command in a way that runs code, or making the script run `--restart-cmd` other than as documented

`--restart-cmd` runs whatever command you give it with your privileges; that it does so is not a vulnerability.

Vulnerabilities in llama.cpp itself or in its release binaries belong with the [llama.cpp project](https://github.com/ggml-org/llama.cpp/security).
