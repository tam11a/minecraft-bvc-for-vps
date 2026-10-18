# Contributing

Thanks for helping out! This repo is deployment glue around [Bedrock Voice Chat](https://www.bedrockvoicechat.com): Docker Compose, config templates, helper scripts and docs.

## Where to report what

| Problem with… | Report to |
|---|---|
| These scripts, compose file, config template or docs | An issue in **this** repository |
| The BVC server, app, addon, audio, sign-in bugs | [Upstream issues](https://github.com/Alaydriem/bedrock-voice-chat/issues) or the [BVC Discord](https://discord.gg/CdtchD5zxr) |

When opening an issue here, include your `BVC_VERSION`, OS/VPS provider, what you ran, and relevant `docker compose logs` output. **Remove secrets** (`DUCKDNS_TOKEN`, `BVC_ACME_API_TOKEN`, login codes) before posting.

## Pull requests

1. Fork and create a branch from `main`.
2. Keep changes focused; one topic per PR.
3. Check your changes:
   - Shell scripts pass `bash -n script.sh` (and ideally [`shellcheck`](https://www.shellcheck.net/)).
   - `docker compose config` succeeds with a copy of `.env.example` as `.env`.
   - If you changed behavior, update `README.md`, `DEPLOY.md` or `docs/` in the same PR.
4. Describe what you tested (e.g. "fresh Ubuntu 24.04 VPS, Realm on 1.26.50, two players").

## Guidelines

- **No secrets in the repo.** `config.hcl` reads secrets with `${env.VAR}`; real values live only in `.env`, which is git-ignored.
- **Pin versions.** Use exact image tags (`1.0.0-beta.23`), never `latest`.
- **Follow upstream.** Prefer settings documented in the [BVC configuration reference](https://www.bedrockvoicechat.com/wiki/reference/configuration/), and link the upstream page when a doc section relies on it.
- **LF line endings.** Enforced by `.gitattributes`; scripts break on Linux with CRLF.
- **Bumping `BVC_VERSION`:** read the upstream release and [upgrade notes](https://www.bedrockvoicechat.com/wiki/upgrading/), update `.env.example` and the compose default together, and mention any required player/addon updates in the PR.

## License

By contributing, you agree your contributions are licensed under the [MIT License](LICENSE) of this repository.
