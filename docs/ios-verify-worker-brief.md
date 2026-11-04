# ios-verify worker brief block

Paste this block into a Feature/QA worker brief so the worker never invents its own sleep/pgrep/lock
loop. Source of truth: [`scripts/ios-verify.sh`](../scripts/ios-verify.sh) and the VERIFY RULE in
[`docs/harness/specs/technical-architecture.md`](harness/specs/technical-architecture.md). Ledger
rule 13 (R1/R2/R3) is the decision record.

```text
iOS verify (do NOT write your own lock/sleep/pgrep loop — the script queues for you):
  scripts/ios-verify.sh                     # queues for one of 2 build slots, then builds + runs tests
  IOS_VERIFY_ONLY_TESTING=<Class1>,<Class2> scripts/ios-verify.sh   # iterate on the classes you touched
  scripts/ios-verify.sh --check-env         # disk + slots + simulator only, no build

  Slots: slot 1 = sim 7CC9393C ("ai-pose-test", the QA lane) + /tmp/dd-shared;
         slot 2 = $IOS_VERIFY_SIM_2 + /tmp/dd-shared-2, and the Feature lane's device is
         CF871F97-1789-4490-B3E3-0B5EFA39F23F ("iPhone 16"), so Feature runs start with
         IOS_VERIFY_SLOT=2 IOS_VERIFY_SIM_2=CF871F97-1789-4490-B3E3-0B5EFA39F23F
         (slot 2 only exists when IOS_VERIFY_SIM_2 is set — it is never defaulted).
         Locks: /tmp/ai-pose-slot-{1,2}; stale locks
  (dead holder, or older than 90 min) are reclaimed automatically, the slot is released on
  EXIT/INT/TERM. The script prints how long it waited. Max 2 concurrent verify runs; everyone else
  does code-only work. Never start a 3rd build by hand and never create a simulator.
  Env: IOS_VERIFY_SLOT=1|2 (force), IOS_VERIFY_SIM / IOS_VERIFY_DD (slot 1 override),
       IOS_VERIFY_TIMEOUT (1400s cap), IOS_VERIFY_FAKE_FREE_KB (fake disk reading for purge tests).
  Disk: below 3 GB free the script auto-purges only the user-approved list (testmanagerd
  attachments of sims that are neither a slot device nor held by a live slot, $TMPDIR/
  maestro_xctestrunner_* older than 10 min, /tmp/dd-* nothing holds) and refuses only below 1.5 GB
  after that. Do not purge by hand. Only the two slot simulators may exist — never create or clone
  one — and the script shuts down/cleans only the slot's own UDID.

  Test classes for this slice: <name the exact classes, e.g. AppConfigTests,
  SessionScopeCoordinatorTests>. Iterate with -only-testing; run the FULL suite once before commit.
```

Rules that come with the block:

- Selectors are bundle-relative and carry the `iosAppTests` target but **not** the source folder:
  `iosAppTests/AppConfigTests`, never `iosAppTests/Services/AppConfigTests` (that selects 0 tests).
  `IOS_VERIFY_ONLY_TESTING` entries are auto-prefixed with the target, so a bare `AppConfigTests` is
  enough and a full `iosAppTests/AppConfigTests/testFoo` form is passed through unchanged.
- A green run with `executed=0` is a false pass and exits non-zero.
- **One Maestro run per host (R4).** Maestro's iOS driver port `127.0.0.1:7001` is host-global, so two
  runs — even on different simulators — kill each other's driver. Only QA runs it; Feature workers never
  run Maestro in any form (including `maestro hierarchy`/`studio`) and never use
  `xcrun simctl launch --console-pty` (killing that console host SIGTERMs the app ~1 s after launch — it
  looks like a crash, but is not). `ios-verify.sh` itself uses `xcodebuild test`, so it is unaffected.
- Release/archive is a separate path and takes no build slot unless it builds on the simulator; its
  disk floor is 5 GB (`MIN_FREE_ARCHIVE_KB` in the script), not 1.5 GB.
- Release artefacts must not live under `/tmp` (a reboot wipes it). The release skill still points
  at `/tmp/aipose-release`; that is a known follow-up, not a rule yet.
