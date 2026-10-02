English | [简体中文](https://github.com/haotian-lu-prog/cold-backup/blob/main/README.md)

# cold-backup

[![npm version](https://img.shields.io/npm/v/cold-backup)](https://www.npmjs.com/package/cold-backup)
[![license](https://img.shields.io/npm/l/cold-backup)](LICENSE)
[![CI](https://github.com/haotian-lu-prog/cold-backup/actions/workflows/ci.yml/badge.svg)](https://github.com/haotian-lu-prog/cold-backup/actions/workflows/ci.yml)

**Cold backup for a workspace full of git repositories.** Artifacts are written straight into a
folder you already sync (OneDrive, iCloud Drive, Dropbox, …) or onto any external disk — your
existing sync client does the upload.

It is not rclone and not restic, and it does not encrypt. It does one thing: turn your workspace
into a pile of **immutable, verifiable, fully restorable files**.

```sh
npm i -g cold-backup      # or ./install.sh (no Node required)
cold-backup --init        # write a config template
cold-backup --status      # did it run? did it upload?
cold-backup               # take a backup
```

> Command output, docs and `docs/decisions.md` are Chinese-first (the author's toolchain language).
> Everything machine-readable — JSON field names, reason codes, upload tokens, exit codes — is
> English, and [`docs/compatibility.md`](docs/compatibility.md) documents the contract.

## What it does

| Target | How | Why |
|---|---|---|
| git repositories | `git bundle create --all`, plus `refs/stash` when present | one file holds **every** ref — including `refs/original/*` and `refs/remotes/*`, which `git push` never carries |
| non-git top-level directories | `tar.gz` snapshot, content fingerprint in the filename | unchanged content adds no new file |
| tool configs (optional) | explicit whitelist + secret pre-scan | only the files you list; anything that looks like a key is dropped instead of uploaded |

Three rules run through all of it:

1. **Idempotent** — the same commit is never packed twice; the same content is never snapshotted twice.
2. **Immutable** — the destination is only ever appended to or pruned, never edited in place.
   Sync clients and background jobs are much happier that way.
3. **"Newest" is decided by filename, not mtime** — cloud clients rewrite mtime when they
   re-materialise files, which would make `--status` lie and `--restore-drill` restore an old copy.

## Install

```sh
npm i -g cold-backup
# or, without Node:
git clone https://github.com/haotian-lu-prog/cold-backup.git
cd cold-backup && ./install.sh     # installs into ~/.local/bin
```

Requirements: `bash` (macOS 3.2 is fine), `git`, `tar`, `gzip`, and `shasum` or `sha256sum`.

## Quick start

```sh
cold-backup --init                      # 1) creates ~/.config/cold-backup/config
$EDITOR ~/.config/cold-backup/config    # 2) set ROOT and DEST
cold-backup --status                    # 3) should say "not backed up yet"
cold-backup                             # 4) first backup
cold-backup schedule install            # 5) daily job (launchd on macOS, cron elsewhere)
```

## Commands

| Command | What it does | Exit |
|---|---|---|
| `cold-backup [--trigger=name]` | take a backup (idempotent) | 0 / 1 |
| `cold-backup --status [--json]` | freshness + upload state; `--json` emits `cold-backup.status/1` | 0 / 1 |
| `cold-backup --verify [--fix]` | verify **every** artifact (real clone + `fsck` for bundles) | 0 / 1 |
| `cold-backup --daily` | catch-up backup + verify + status (this is what the scheduler runs) | 0 / 1 |
| `cold-backup --prune-orphans [--apply]` | list (default) or delete leftovers that match no target | 0 / 1 |
| `cold-backup --restore-drill [dir]` | mirror-clone every latest bundle and compare refs & commit counts | 0 / 1 |
| `cold-backup schedule install\|uninstall\|status [--dry-run]` | manage the daily job | 0 / 1 / 2 |
| `cold-backup --init [--force]` | write a config template | 0 / 2 |
| `cold-backup --version` | version + active config file | 0 |

`--status` and `--version` are **strictly read-only**: no directories created, no files written,
no log rotation.

## Configuration

Precedence: **flags > environment > config file > defaults**. The config file is `KEY=VALUE` at
`~/.config/cold-backup/config` (override with `--config` or `COLD_BACKUP_CONFIG`).

| Key | Env | Default | Meaning |
|---|---|---|---|
| `ROOT` | `DEV_ROOT` | `~/dev` | workspace root to back up |
| `DEST` | `COLD_BACKUP_DEST` | none (**required**) | where artifacts go. **Must be outside `ROOT`** — inside it, snapshots would swallow the backup itself and grow every run, so the tool refuses |
| `LOGDIR` | `COLD_BACKUP_LOGDIR` | macOS `~/Library/Logs/cold-backup`; else `~/.local/state/cold-backup` | logs, lock, `last-ok`, `last-failure` |
| `DEPTH` | `COLD_BACKUP_DEPTH` | `3` | how deep to look for `.git` under ROOT |
| `KEEP` | `COLD_BACKUP_KEEP` | `10` | artifacts kept per target; older ones rotate out |
| `SNAPSHOTS` | `COLD_BACKUP_SNAPSHOTS` | `1` | snapshot non-git top-level dirs |
| `INCLUDE_ENV` | `COLD_BACKUP_INCLUDE_ENV` | `0` | include `.env` files in snapshots (excluded by default: plaintext secrets) |
| `EXCLUDES` | `COLD_BACKUP_EXCLUDES` | empty | extra tar excludes, space separated |
| `CONFIGS` | `COLD_BACKUP_CONFIGS` | `off` | config whitelist, `<label>|<home>|<rel,rel>`, `;`-separated |
| `NO_NOTIFY` | `COLD_BACKUP_NO_NOTIFY` | `0` | `1` disables desktop notifications |
| `UPLOAD_GRACE` | `COLD_BACKUP_UPLOAD_GRACE` | `600` | seconds before an artifact counts as "not uploaded" |
| `WORKSPACE_ID` | `COLD_BACKUP_WORKSPACE_ID` | host + ROOT fingerprint | ownership marker (see below) |

`COLD_BACKUP_DISABLE=1` makes backup mode exit 0 immediately (git hooks use it as a kill switch).

## Restore

See [`docs/restore.md`](docs/restore.md) for the full manual. The short version:

```sh
git clone --mirror "<DEST>/repos/<label>/<file>.bundle" /tmp/restore.git   # everything
git clone "<DEST>/repos/<label>/<file>.bundle" /tmp/restore                # working copy
tar -xzf "<DEST>/snapshots/<label>/<file>.tar.gz" -C /tmp/restore
cold-backup --restore-drill                                                 # prove it, don't assume it
```

**Not covered, on purpose:** uncommitted/untracked changes, hidden directories such as
`.worktrees/`, credentials and session history in your home, and re-installable bulk
(`node_modules/`, build output). This is a second layer behind `git push`, not a substitute for
committing.

## Scheduling

```sh
cold-backup schedule install --at 12:00
cold-backup schedule install --dry-run
```

Full details in [`docs/scheduling.md`](docs/scheduling.md), including the macOS catch: if `DEST`
lives under `~/Library/CloudStorage/` or `~/Library/Mobile Documents/`, a background job cannot
read existing files there (TCC). Either grant Full Disk Access to the program that runs the job, or
point the job at an already-authorised program with `--program /path/to/program`.

## Sharing one destination between machines

Every target directory gets a `.cold-backup-owner` marker (a workspace ID, by default derived from
hostname + root path). A directory owned by a *different* workspace is reported but **never**
written to and **never** deleted — `--prune-orphans --apply` skips it and a backup run refuses it
and exits non-zero. Set the same `WORKSPACE_ID` on both machines if you genuinely want them to
share one set of artifacts.

## For downstream consumers

`cold-backup.status/1` is a stable contract consumed by
[dsh-cold-backup](https://www.npmjs.com/package/dsh-cold-backup) (a DeepSeek Harness panel) and by a
home-grown macOS panel. Fields, reason codes, upload tokens and exit conventions are documented in
[`docs/compatibility.md`](docs/compatibility.md).

## Platform support, honestly

- **macOS**: in daily use; the full end-to-end suite passes, including under bash 3.2.
- **Linux**: every BSD-ism (`stat -f`, `date -j`, `shasum`) goes through a compatibility layer and
  CI runs the same suite on `ubuntu-latest`, but **the author has not hand-verified a real Linux
  box** — a green CI badge is not the same thing as "works on your distro".
- Upload-state probing uses macOS `mdls`; elsewhere it honestly reports "unknown" instead of
  pretending your files are uploaded.

## Tests

```sh
npm test          # = bash test/lint.sh && bash test/selftest.sh
```

Everything runs inside `mktemp -d` sandboxes — your real backup destination is never touched.
The linter catches the classic macOS bash 3.2 trap (a full-width character right after a variable
swallows it into the variable name), bash-4-only syntax, version mismatches, and personal paths
leaking into a public package.

## License

MIT — see [LICENSE](LICENSE).
