---
work_item: 3
title: Integrate platform contracts and quality-test matrix
status: pending
priority: P2
effort: M
dependencies:
  - 2
decision_dependencies:
  - PA-015-01
  - PA-015-02
  - PA-015-03
  - PA-015-04
  - PA-015-05
  - PA-015-06
---

# Work Item 3: Integrate platform contracts and quality-test matrix

## Kind

`technical` / `verification`

## Goal

Close production integration and quality evidence around Settings for the
authority-approved v1 scope: Account push seam, external Support/Terms/Privacy
URLs, camera access status with iOS Settings shortcut, iOS-first delivery, and no
v1 persistence store. Prototype-hash ledger reconciliation is **complete**
(2026-09-05; read-only `sha256sum` sign-off; prototype bytes not edited).

## Authority reference

**Canonical record:** [FEAT-015 Feature](../../features/FEAT-015-manage-app-settings-and-preferences.md)
→ Product Authority decision matrix (`PA-015-01`…`PA-015-06`). This Work Item
uses execution and traceability checks below; it does not restate decision rows.

About is a fixed product/prototype surface, not an additional Product Authority ID.

## Integration consequences (v1)

| ID | Integration consequence |
| --- | --- |
| `PA-015-01` | Voyager push from Account; one Back; no claim of existing production route. |
| `PA-015-02` | Omit `SettingsPreferenceStore`, SQLDelight Settings tables, and persistence/write/relaunch/failure tests. |
| `PA-015-03` | Host `openSupport()` opens `https://forms.gle/sample-aipose-feedback`; report `Opened`/`Failed`. |
| `PA-015-04` | Host opens Terms and Privacy URLs; separate rows; external browser. |
| `PA-015-05` | iOS actual first; Android labeled deferred. |
| `PA-015-06` | Settings permission reader for camera access only; separate from `CameraController` capture config. |

## Quality matrix

| Concern | Required evidence | Failure that blocks acceptance |
| --- | --- | --- |
| State/owner | reducer and fake-port tests for session/destination outcomes | stale protected state or false success |
| Navigation | push from Account (`PA-015-01`), Back, re-entry refresh, stale-session rejection | duplicate stack or dead end |
| Persistence | omitted in v1 (`PA-015-02`) | any v1 preference store, write, or persistence-failure test claim |
| Permissions/legal/support | fake matrix including `openSupport()`; prototype Allowed + iOS shortcut and external URLs | invented URL or Camera config in Settings |
| Accessibility | semantics/focus/target-size on Settings rows and About sheet | unlabeled action or dead-end modal |
| Platform parity | iOS compile/runtime; Android explicit gap (`PA-015-05`) | Android claimed without target |

## Prototype verification checks

- `node --check docs/prototype/scripts/settings.js`
- `rg -i unavailable` on three prototype files → zero matches
- Literal presence: `Snap Pose`, `v1.0.0`, `Build 42`, `© 2026`, `Allowed`,
  `https://forms.gle/sample-aipose-feedback`, `https://aipose.app/terms`,
  `https://aipose.app/privacy`
- `sha256sum` on the five owned Markdown paths at handback; Plan prototype-hash
  ledger reconciled to verified current hashes (html `53b5425f…`, css `dc64735f…`,
  js `45e33665…`; prototype paths not edited in this lane)
- Owned docs: Feature holds the sole six-row Product Authority matrix; Plan and
  Work Items reference it without duplicated decision rows; no additional
  `PA-015-*` decision IDs

## Acceptance and evidence

- Requirement coverage matches resolved scope; v1 has no persistence and no
  persistence-failure tests; post-v1 persistence coverage deferred only.
- Final `DOC_UPDATE_HANDBACK` lists the five owned Markdown paths, reconciled
  prototype ledger hashes, candidate identity, checks run, read-only prototype
  verification summary, and explicit statement that no formal approval was given.
- Unsupported Android/UI automation gaps labeled deferred (`PA-015-05`).

## Required evidence

Requirement-to-test matrix; prototype behavior matrix; scoped `git status`/`git diff`
proof limited to the five-file Markdown write-set; `DOC_UPDATE_HANDBACK` to
parent. No Cook or `READY_FOR_WORK` claim.

## Hash ledger reconciliation (complete, 2026-09-05)

Work Item 3 **hash-reconciliation execution is complete** for this planning lane.
Prototype bytes were not edited.

| Prototype path | Verified SHA-256 |
| --- | --- |
| `docs/prototype/screens/settings.html` | `53b5425ff011d7bf3bd6fd561fb429d53265bdc0939835a73fb9170f63a72aa1` |
| `docs/prototype/styles/settings.css` | `dc64735f40cd9ebf24e30230ff3a83b295a9f4780e424164b1b31147889ca9e2` |
| `docs/prototype/scripts/settings.js` | `45e336657aa3638b1dddf083b4f06d4f4e54098441243d72aa0850427db5243c` |

**Prototype candidate identity:**
`b59cca2a291c8557469970f955e81c5448c73f4476c94f46d9a55ec5d62430b3`

Checks run: `node --check docs/prototype/scripts/settings.js` (pass); `rg -i
unavailable` on three prototype files (zero matches); `sha256sum` matches ledger
above.

**Not implied:** formal Feature approval, Plan approval, Cook, or `READY_FOR_WORK`.
Work Item 3 frontmatter remains `pending` for future production integration and
quality-test matrix execution (Cook). Feature remains `draft`; Plan remains
`pending`; Work Item 1 remains `completed`.
