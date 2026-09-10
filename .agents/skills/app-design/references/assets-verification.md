# Visual assets and verification

Read this reference when producing artwork or validating a running flow.

## Asset direction

Define one asset system before production:

```text
style family, palette, lighting, texture, subject grammar,
composition rules, background treatment
```

Generate or produce multiple candidates, choose a direction, align the set,
inspect it inside the actual UI, post-process, optimize, and test both themes.
Repeated assets should share palette, lighting, line weight/material,
perspective, texture, and background treatment. Produce sufficient source
resolution and downscale; do not upscale low-quality originals.

Reject style or palette drift, inconsistent lighting, halos, unwanted text,
watermarks, compression artifacts, incompatible cropping, and generic
unart-directed output. Check safe areas, focal points, text placement, button
overlap, and rendered size.

## Verification loop

```text
Implement → Run → Observe → Interact → Record/measure → Fix → Re-verify
```

Inspect actual rendered screens for alignment, optical centering, clipping,
hierarchy, long text, small viewports, large text, theme variants, and
loading/empty/error states. For motion, review once in real time and once frame by
frame; check dropped frames, flashes, keyboard jumps, gesture cancellation, and
intermediate-theme or double-render artifacts.

Exercise boundaries, not only the happy path:

- every forward and Back path, modal/sheet presentation, cancellation, and one-way door;
- keyboard appearance/dismissal, rapid or repeated taps, double submission, and interrupted gestures;
- scroll extremes, long text, empty data, slow loading, failure, offline, background/foreground, kill/relaunch;
- representative modern and small phones, every supported mobile platform, and large-screen devices when supported.

Re-observe after small fixes. Do not batch unrelated UI changes before checking
the result again.

## Definition of done

- [ ] Adopted pattern, primary goal, hierarchy, and navigation are documented.
- [ ] Applicable loading, empty, error, offline, and long-content states work.
- [ ] Themes, safe areas, large text, contrast, target sizes, and Reduce Motion are checked.
- [ ] Motion has a purpose and performance claims have measurements.
- [ ] Actual UI and complete flow were exercised on a running target.
- [ ] Adversarial cases and representative device profiles were checked.
- [ ] No known observable defect remains; unverifiable criteria are called out.
