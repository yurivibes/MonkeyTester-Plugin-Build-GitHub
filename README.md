# MonkeyTester-Plugin-Build-GitHub

`build-github` is a MonkeyTester build plugin for app repos hosted on **GitHub**
(github.com or GitHub Enterprise Server): it implements
`BUILD_PLUGIN_API.md` (contract `monkeytester-build-plugin`,
version 1, kept in the MonkeyTester repo) with builds that run **on the plugin's
own host**. The viewer's Build & Test page asks it for a repo's branches and test
cases and to build a branch; the plugin fetches the code from GitHub with a
read-only token, runs the app repo's `.monkeytester/build-<platform>.sh` scripts
here (Android and iOS on a Mac, Android only on Linux) and uploads the built apps
to the viewer with the viewer's `submit.py`, so the run attaches to the build.

It is a GitHub-only copy of MonkeyTester-Plugin-Build-Local (which can talk to Gitea
or GitHub, one code host per running instance). Use this plugin when your
GitHub-hosted projects should build next to a build-local instance that serves
Gitea, or when you only use GitHub. Both share the same contract, app-repo scripts
and `/health` shape, so the viewer treats them alike.

The code-host URL and token live only in this plugin; the viewer never sees the
token. A build that fails is not an HTTP error: `GET /builds/<ref>` is `200` with
a failed conclusion. A platform that failed to build while another one built still
ends the build as `success`: the failed platform is uploaded as a build error with
its log, so its devices show every test as Unavailable with View logs. Builds run
one at a time (FIFO queue); queued or running builds can be cancelled
(`POST /builds/<ref>/cancel` terminates the script's process group), and the build
log is tail-able (`GET /builds/<ref>/log?offset=` with `X-Log-Size` /
`X-Log-Complete`).

- Default port: **8095**
- Python 3.10+, standard library only. Runs on Linux and macOS.

## Requirements per host

- **Mac (builds Android and iOS):** macOS with Xcode (the plugin detects iOS with
  `xcodebuild -version`), the Android SDK (detected via `ANDROID_HOME` /
  `ANDROID_SDK_ROOT` / `~/Library/Android/sdk` / `~/Android/Sdk`), a JDK for the
  Android build, and — for the signed `.ipa` — the code-signing identity in the
  **login keychain of the user the plugin runs as** (the launchd agent runs as an
  ordinary user; keychain access needs the `Aqua` session type, see the plist).
  The provisioning profile must cover each test iPhone's UDID.
- **Linux (Android only):** the Android SDK plus a JDK; iOS is not offered.

## Install

### With Nix (Linux or macOS)

```sh
git clone <repo-url> MonkeyTester-Plugin-Build-GitHub
cd MonkeyTester-Plugin-Build-GitHub
nix run .            # plugin on :8095
nix run .#tests      # unit tests against the fake GitHub
```

The flake builds from git-tracked files only, so `git add` new files before
`nix run`.

To keep it running:

- Linux: `packaging/systemd/monkeytester-build-github.service` (user unit; the
  install steps are in the file's header; Android only).
- macOS: `packaging/launchd/com.blackjackfruit.monkeytester-build-github.plist`
  (LaunchAgent; replace `CHECKOUT_DIR` and `PYTHON`).

### Without Nix

Any `python3` 3.10 or newer works, with no extra packages:

```sh
python3 build_plugin.py
python3 -m unittest discover -s tests -v
```

## Configuration

| Env var | Default | Meaning |
|---|---|---|
| `PLUGIN_HOST` | `0.0.0.0` | listen address. The default is the LAN, because the viewer on the Linux host reaches the Mac over it — so the default **needs `PLUGIN_TOKEN`**. `127.0.0.1` listens on this machine only |
| `PLUGIN_PORT` | `8095` | listen port |
| `PLUGIN_TOKEN` | unset | pairing token: every request except `GET /health` must send it as `X-Plugin-Token` or `Authorization: Bearer`. **Mandatory when `PLUGIN_HOST` is not loopback** (`127.0.0.1`, `::1`, `localhost`): without it the plugin refuses to start (exit status 2). Generate one with `python3 -c 'import secrets; print(secrets.token_urlsafe(32))'` |
| `BUILD_PLUGIN_STATE_DIR` | `~/.config/monkeytester-build-github/` | `config.json` (code host + token + viewer URL, mode 0600), `builds.json`, `checkouts/`, `out/` (newest 50 builds keep their files) |
| `BUILD_GITHUB_PLATFORMS` | auto-detect | e.g. `android` to force Android only |
| `BUILD_GITHUB_TIMEOUT_ANDROID` / `BUILD_GITHUB_TIMEOUT_IOS` | `3600` | seconds a platform's build script may run |

The token is plaintext at rest in `config.json` (mode 0600): the plugin reads it
without a person present, so encrypting it on the same disk would not add real
protection. It is never returned by any endpoint, never written to a build log or
to any repo's `.git/config`, and passed to git only per command via environment.

## Register the plugin in the viewer

1. Set `PLUGIN_TOKEN` (see [SECURITY.md](SECURITY.md#token-setup)) and start the plugin.
2. In the viewer: **Settings → Build & Test → Add build plugin**. Name `build-github`,
   address `http://<host>:8095`, and the same pairing token as `PLUGIN_TOKEN`.
3. Click **Configure** on the plugin and enter:
   - the **code host**: GitHub (the only choice this plugin accepts; any other
     `forge_kind` is refused with `400`),
   - its **URL**: blank or `https://github.com` for github.com (stored as the API
     base `https://api.github.com`), or `https://<host>` / `https://<host>/api/v3`
     for GitHub Enterprise Server,
   - a **read-only token** — it only reads the repo and fetches it with git: a
     fine-grained token with Contents: read + Metadata: read on the repos you
     build, or a classic token with the `repo` scope for private repos (a token
     is needed for public repos too: it identifies the plugin and lifts the
     anonymous API rate limit),
   - the **viewer URL** (prefilled with the address the browser is using) — the
     plugin uploads to it.
   The plugin checks the token against the code host (who it belongs to) before
   it saves anything.
4. Add projects (one repo each) and pick `build-github` as their build plugin.

## The app repo side

Commit one script per platform at the paths the plugin reports in `/health`
`recipes`: `.monkeytester/build-android.sh` and `.monkeytester/build-ios.sh`
(`GET /template?platform=` returns the example scripts — download them from
Settings and commit them to your repo). The plugin runs each with `bash` from the
root of a clean checkout of the branch, with:

| Variable | Value |
|---|---|
| `MT_PLATFORM` | `android` or `ios` |
| `MT_OUTPUT` | where the script must write the app: a `.apk` (Android) or a signed `.ipa` (iOS) |
| `MT_BRANCH` | the branch being built |
| `MT_CASES` | comma-separated case names |
| `MT_REQUEST_ID` | the viewer's build id |

Exit status `0` with a non-empty file at `MT_OUTPUT` is a successful build;
anything else is a build error, reported with the script's last `error:` lines
and its log.

## Endpoints

The full contract is `BUILD_PLUGIN_API.md` in the MonkeyTester repo. Every route
except `GET /health` needs the pairing token when `PLUGIN_TOKEN` is set.

| Route | Answer |
|---|---|
| `GET /health` | contract, plugin name/version, code host, platforms, `recipes`, capabilities; `"docs": "/docs"` while this README is readable (omitted otherwise) |
| `GET /docs` | this README rendered as a self-contained HTML page (`text/html`, strict CSP, no scripts); 404 JSON if README.md is missing. The viewer shows it through `/plugins/docs/build-github` |
| `GET` / `POST /config` | code host kind + URL + user and viewer URL (the token is never returned) / save them |
| `GET /template?platform=` | example `.monkeytester/build-<platform>.sh` |
| `GET /repos/<owner>/<repo>[?branch=]` | check a repo (and branch) |
| `GET /repos/<owner>/<repo>/branches` | the repo's branches |
| `GET /repos/<owner>/<repo>/cases?ref=` | test cases on a ref |
| `POST /builds` | queue a build; `GET /builds/<ref>` its status |
| `GET /builds/<ref>/log?offset=` | the build log from `offset` |
| `POST /builds/<ref>/cancel` | stop a queued or running build |

`/docs` reads `README.md` next to `build_plugin.py` at request time. The
launchd/systemd units run from the checkout and the Nix flake copies every
git-tracked file, so README.md is present in all three; an install without it
just leaves `docs` out of `/health`.

## Security

See [SECURITY.md](SECURITY.md) for the threat model, token setup (launchd
`EnvironmentVariables`, systemd `Environment=`) and what is not covered (no TLS,
plaintext secrets at rest). In short: on a LAN bind the plugin will not start
without `PLUGIN_TOKEN`; `/health` is the only unauthenticated route and carries no
secret or configuration.

The plugin **runs the scripts of the branch it builds** — run it as a dedicated,
never-root user, and only add trusted repos as projects: a repo's build script
runs with that user's environment, keychain and SDKs. The forge token is read-only
and stays out of every log and git config. Builds are one-at-a-time; use
`POST /builds/<ref>/cancel` to stop a queued or running build (the script's whole
process group is terminated), and `GET /builds/<ref>/log` to watch what it is
doing.

## Tests

`python3 -m unittest discover -s tests -v` — fake GitHub and a fake viewer, all in-process on 127.0.0.1; a real forge or viewer is never contacted.
`nix run .#tests` and CI (`.github/workflows/test.yml`) run the same command.
