# P001 implementation manifest

Scope: architecture audit, immutable source inventory and documentation-only CI.
No port, runtime patch, installer, live plist or device operation is included.

- Target: nghianguyen150612/Navidrome-iOS.
- Starting checkout/master SHA: ec2e0a9ea9cd7c2f08f930fc0579b991e1fe0900.
- Base: upstream v0.64.2, 101145742f4762164202cb4858c9126258bdc463.
- iOS branch created at that base; feature feat/p001-ios-baseline-architecture.
- PR base: iOS. master is untouched. Ending SHA is the commit containing this
  manifest (`git rev-parse HEAD`); it cannot be embedded into itself.
- Full dependency versions, reference SHAs and selected content hashes: audit.json.
- Collection environment: Linux, Python 3, git and HTTPS remote source inspection;
  no Apple SDK, device session or usable Go toolchain established.

## Validation record

| Check | Status | Evidence / limit |
| --- | --- | --- |
| Baseline tag/SHA | PASS | git ls-remote upstream refs/tags/v0.64.2; git rev-parse v0.64.2^{commit} |
| Branch ancestry | PASS | iOS created at base; feature from iOS; master matched upstream remote master |
| Upstream source unchanged | PASS | Scaffold compares complete changed-path allowlist and baseline hashes |
| Inventory/contracts/docs | PASS | python3 scripts/ios/validate_p001.py; links, paths, all module versions and milestones |
| Diff whitespace | PASS | git diff --check, staged equivalent and final base diff |
| CI scaffold | PASS locally | Same standard-library command as ios-p001.yml; remote result reported in PR |
| Go/application tests | BLOCKED | /usr/bin/go version returns Unknown option; no application source changed |
| Apple compile/link | BLOCKED | No qualified Apple SDK/toolchain |
| iPad runtime/lifecycle/stream/memory | NOT TESTED | No device execution or measurements |
| Installer rollback/security execution | NOT TESTED | Contracts only; future fixtures required |

PASS entries are recorded after running the listed checks; remote CI status and
PR URL/state are external delivery evidence, not fabricated here. Check current
PR checks before merge. No merge is authorized by this document.

Negative controls also PASS: the validator rejected a temporary upstream Go
source edit and a temporary canonical alias-path change; both were restored
byte for byte before the final successful run.

## Reproduce

Fetch the base commit/tag, then run `python3 scripts/ios/validate_p001.py` and
`git diff --check 101145742f4762164202cb4858c9126258bdc463 HEAD`.
CI fetches history and the exact upstream tag explicitly: the fork does not
publish that tag. An initial CI run exposed this missing prerequisite; the
workflow was corrected without changing the baseline check. The validator requires git/Python, does not fetch packages
or execute Navidrome, and rejects any P001 change outside its explicit allowlist.
The baseline's complete source is preserved byte for byte.

Review ARCHITECTURE.md for feasibility/security, COMPATIBILITY.md for blockers,
BUILD_PLAN.md for experiments and INSTALLER_CONTRACT.md for paths/transactions.
P002 is the runtime qualification described in ROADMAP.md. Stop after P001;
no automatic P002, release or merge.
