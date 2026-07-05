# App Store Submission Flow

When the user says **提审**, **submit for review**, **发版**, or **准备上架**, treat it as a submission prep task — not just uploading a build.

## Version baseline

提审默认以 **App Store 线上已发布版本** 为基准，而不是 `VERSION` 或 git tag。

| File | Meaning |
|------|---------|
| `SHIPPED_VERSION` | 线上正在卖的版本（当前 `1.0.8`） |
| `VERSION` | 仓库当前开发/提审版本 |
| 默认提审目标 | `SHIPPED_VERSION` 的下一个 patch（`1.0.8` → `1.0.9`） |

同一版本可能被拒后多次提审。多次提审时 **marketing version 不变**，只递增 build 号、更新 metadata。

## Default behavior

Always do these steps unless the user explicitly says otherwise:

1. **Resolve target version** = `SHIPPED_VERSION + 1 patch` (unless user names a version).
2. **Detect mode**:
   - **new** — first 提审 for this target: bump marketing version, scaffold metadata, increment build.
   - **resubmit** — target already prepared: keep marketing version, increment build only, update metadata.
3. **Update What's New** in `en-US.json` and `zh-Hans.json`.
4. **Commit, tag (first time only), and push** before building or uploading.
5. **Build, upload, stage metadata, and submit** on App Store Connect.
6. **After approval and going live**, run `./scripts/mark-shipped.sh <version>`.

Do not skip metadata updates. Do not bump marketing version on resubmit. Do not upload a build before the release commit is pushed to `origin`.

## Quick start

```bash
./scripts/prepare-submission.sh
```

Explicit target (must be greater than shipped):

```bash
./scripts/prepare-submission.sh 1.0.9
```

## Canonical sources

| What | Where |
|------|-------|
| App Store live version | `SHIPPED_VERSION` |
| Repo / commit version | `VERSION` |
| Build number | `CFBundleVersion` in `iPhone/Info.plist` and `WatchRemote/Info.plist` |
| Per-version ASC copy | `metadata/version/<version>/en-US.json`, `zh-Hans.json` |
| App-level ASC copy | `metadata/app-info/` |

App Store app ID: `6760964443`

## Agent checklist for 提审

### 1. Prepare version and metadata

```bash
./scripts/prepare-submission.sh
```

The script prints `new` or `resubmit` mode. Verify:

- Target version = `SHIPPED_VERSION + 1` by default
- `metadata/version/<version>/` exists
- `whatsNew` is updated for this submission attempt

Use `asc-whats-new-writer` to draft notes from commits since `v<shipped-version>`.

### 2. Commit, tag, and push

First 提审 for a version:

```bash
./scripts/commit-release.sh
```

Resubmit after rejection:

```bash
./scripts/commit-release.sh --resubmit
```

Resubmit keeps tag `v<version>` unchanged and only pushes new commits.

### 3. Build and upload

Ensure the uploaded build's marketing version and build number match the repo.

### 4. Stage metadata on App Store Connect

```bash
asc validate --app "6760964443" --version "<version>" --platform IOS --output table

asc release stage \
  --app "6760964443" \
  --version "<version>" \
  --build "BUILD_ID" \
  --metadata-dir "./metadata/version/<version>" \
  --confirm
```

### 5. Submit for review

```bash
asc review submit --app "6760964443" --version "<version>" --build "BUILD_ID" --confirm
```

### 6. After going live

```bash
./scripts/mark-shipped.sh <version>
git add SHIPPED_VERSION
git commit -m "<version>: chore: mark <version> as shipped"
git push origin HEAD
```

## Scenarios

### First 提审 after 1.0.8 is live

- `SHIPPED_VERSION` = `1.0.8`
- `VERSION` = `1.0.8`
- `./scripts/prepare-submission.sh` → **new**, target `1.0.9`
- Creates `metadata/version/1.0.9/`, bumps marketing version, increments build

### Second 提审 (1.0.9 rejected, fix and resubmit)

- `SHIPPED_VERSION` = `1.0.8` (still live)
- `VERSION` = `1.0.9`
- `./scripts/prepare-submission.sh` → **resubmit**, target `1.0.9`
- Marketing version stays `1.0.9`, build number increments, metadata updated
- `./scripts/commit-release.sh --resubmit`

### After 1.0.9 goes live, next 提审

```bash
./scripts/mark-shipped.sh 1.0.9
./scripts/prepare-submission.sh    # → new, target 1.1.0
```

## Version rules

- Commit messages must match `VERSION` (see `docs/agents/commit-convention.md`).
- Day-to-day feature commits use `SHIPPED_VERSION` until `prepare-submission.sh` bumps `VERSION`.
- Never advance marketing version beyond `SHIPPED_VERSION + 1` unless the previous target is already live.

## What's New guidance

- Lead with the most user-visible change in the first sentence.
- Update both `en-US` and `zh-Hans`.
- On resubmit, mention review fixes if relevant.