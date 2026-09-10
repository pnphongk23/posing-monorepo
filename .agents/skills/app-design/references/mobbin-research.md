# Mobbin research guide

## Purpose

This is a reusable workflow for researching any mobile feature or flow with Mobbin. It explains how to move from a broad product comparison to evidence-backed UX decisions. The camera study at the end is a worked example, not the scope of this guide.

The output should be a decision artifact, not a moodboard: each adopted idea needs a source, an observed pattern, the product principle behind it, and a product-specific implementation.

## Research contract

Before opening Mobbin, define:

- **Task:** what the user is trying to do.
- **Primary goal:** the one outcome the screen must make easy.
- **Flow boundary:** where the feature starts and where it hands off to another feature.
- **States to study:** at minimum, entry, active/content, loading, empty/error, and completion when they apply.
- **Output:** the decisions this research must inform, such as navigation, hierarchy, controls, or feedback.

Research behavior and flow, not just visual styling. A useful reference can be visually different from the product being designed if it solves the same user problem.

## Standard Mobbin flow

### 1. Start with a collection

Open a Mobbin collection or search result for the platform and screen pattern closest to the task. Start broad enough to see the category, then narrow by behavior rather than brand or color.

Prefer queries that describe a job or interaction: scanner, picker, onboarding, checkout, editor, feed, permission, or confirmation. Record the collection URL and the date of the study; result counts and rankings can change.

Do not stop at the first attractive screen. The collection is for finding comparable flows and contrasting solutions.

### 2. Choose anchor references

Open three to five detailed screens from different products or product types. Use the anchors to answer:

- What owns the surface: content, preview, form, or task result?
- What is the primary action, and how is it separated from secondary actions?
- Which controls are always visible and which are contextual?
- How does the user enter, complete, cancel, or leave the task?
- Is a control a push screen, sheet, modal, inline state, or transient message?
- What changes during loading, success, permission denial, empty, or error?

Capture the whole screen context and the transition implied by the screen. A single thumbnail is not enough evidence for navigation or state behavior.

### 3. Expand with `See similar`

Use `See similar` as a branching research tool, not just a way to find more screenshots:

1. Start from the strongest anchor for the primary task.
2. Open `See similar` and inspect the resulting grid for repeated structures and meaningful outliers.
3. Select examples that add a different product context or interaction model; skip near-duplicates.
4. Open `See similar` again from a selected example and keep the chain: `anchor → similar set → selected reference`.
5. Repeat until the same patterns recur or a new branch stops adding insight. In practice, three to five branches is usually enough for one feature study.

Sample deliberately across:

- capture versus browse versus edit;
- first-use versus repeat-use;
- primary action versus fallback/import action;
- ready versus loading/result/error;
- compact controls versus a more explicit labeled alternative.

The point is to discover the design space and its boundaries. Record both the common pattern and the case where a product intentionally breaks it.

## Constrained-access playbook

When Mobbin access is limited, optimize for evidence diversity rather than the
largest possible screenshot count.

### Branch by filter dimension

Use the four visible filter families deliberately:

1. **Screens** gives the broad interaction intent, such as Browse & Discover,
   Bookmarks & Collections, Home, or News Feed.
2. **Categories** changes the product context, such as Photo & Video, Social
   Networking, Productivity, or Travel & Transportation.
3. **UI Elements** narrows the structure, such as Gallery, Card, Stacked List,
   Search Bar, Tab, or Top Navigation Bar.
4. **Flows** isolates behavior, such as Switching View, Filtering & Sorting,
   Saving to Collection, Searching & Finding, or Selecting & Choosing.

For a visual collection or gallery/list study, a high-yield sequence is:

```text
screen intent
  → matching product category
  → matching UI element
  → contrasting category
  → behavior flows
```

For example, `Browse & Discover → Photo & Video → Gallery` exposes media
layouts; adding `Social Networking` provides an equal-grid contrast; switching
to `Bookmarks & Collections → Photo & Video` reveals personal-library and
history patterns; `Switching View`, `Filtering & Sorting`, and `Saving to
Collection` cover transitions and secondary actions. This is a branching
strategy, not a fixed list of filters for every feature.

### Spend detail opens on distinct evidence

- Use the collection grid to scan broadly, then open three to five anchors from
  different products or product types. If the category is varied, aim for about
  ten total references while keeping detailed opens selective.
- Prefer one strong reference per product, unless the second screen proves a
  different state or interaction model. Repeated screens from the same app are
  not independent evidence.
- For a flow, inspect the sequence rather than one frame. Record the number of
  screens, the first action, the intermediate state, the completion state, and
  the Back/cancel implication.
- A detailed screen may expose `Found in` flows and `See similar`; use those as
  branch leads, but keep the source chain so the final decision remains
  auditable.

### Verify that a filter actually applied

Mobbin can leave the filter popover open after an option is selected. Close the
popover, then verify both the URL parameters and the visible `Showing` count.
If the result grid is blank immediately after a valid selection, allow one load
cycle before calling it empty. A screenshot can also contain unloaded/blank
thumbnails; use the accessibility/DOM result names and a later visual capture
as supporting evidence, not as a reason to invent a missing result.

### Evidence log for each branch

Keep a compact row for every branch:

```text
Filter path:
Collection URL:
Research date:
Visible result count:
Reference product + detail URL:
User task:
Observed structure/state:
Navigation or transition:
Primary / secondary actions:
Back or cancel behavior:
Why it adds new evidence:
```

Separate visible observation from interpretation. For example, “two columns
have different image heights” is evidence; “use masonry in our gallery” is a
product decision that still needs to account for chronology, comparison, and
the product's own data.

Stop exploring a branch when it only returns near-duplicates or when the same
pattern recurs across distinct products. End with at least one contrast and
mark states Mobbin does not show as open questions rather than filling the gap
with assumptions.

### 4. Record evidence while browsing

For every useful reference, write short notes under the same fields:

```text
Reference: product + screen/flow URL
User task: what this screen helps the user do
Observed pattern: visible structure or interaction
State: entry / active / loading / result / empty / error
Navigation: push / sheet / modal / inline / transient
Primary action:
Secondary actions:
Back or cancel behavior:
Why it is relevant:
```

Keep observations separate from interpretation. “Image icon sits beside the shutter” is evidence. “Import should be visually secondary” is a principle derived from evidence.

### 5. Synthesize with four layers

Use this sequence for every decision:

| Layer | Question | Example |
| --- | --- | --- |
| Reference | Where was this observed? | Venmo camera screen |
| Pattern | What behavior or structure repeats? | Image import is an icon-only secondary action |
| Principle | Why does the pattern work here? | The primary capture task stays visually dominant |
| Product-specific implementation | What will we do in our product? | Keep guide selection icon-only and return to the initiating camera |

This prevents a screenshot from becoming an unexplained visual instruction. Adopt the principle, then translate it through the product's own tokens, content model, platform conventions, and accessibility requirements.

### 6. Turn references into a flow model

After synthesis, map the feature as states and transitions rather than a list of screens:

```text
Entry → primary task → in-progress state → result
             ├─ secondary setup or picker
             ├─ cancel / Back
             └─ permission, empty, or error recovery
```

For each node, decide:

- what remains visible from the initiating feature;
- whether the next surface is pushed, presented as a sheet, or shown inline;
- what Back does first when local state is open;
- how the user returns after completing a subordinate task;
- which feedback is persistent, inline, or transient;
- whether the flow is safe to repeat without accumulating screens in the Back stack.

Use a dedicated subordinate screen for a self-contained task with its own browsing or selection model. Use a sheet for a short interruption that should preserve the initiating context.

### 7. Write Adopt, Avoid, and open questions

End the research with three short sections:

- **Adopt:** patterns supported by multiple references and relevant to the product goal.
- **Avoid:** patterns that add chrome, break context, or solve a different task.
- **Open questions:** behavior Mobbin cannot answer, such as device permission timing, real loading duration, or the product's data constraints.

Do not turn an absence of evidence into a claim. If Mobbin does not show a state, mark it as an implementation question and verify it in the prototype or with platform guidance.

## Reusable output template

````markdown
# [Feature] Mobbin research

## Reference study
- Task:
- User goal:
- Flow boundary:
- Platform / collection:
- Research date:
- `See similar` branches:

## Observed patterns
- ...

## Meaningful variations
| Variation | Seen in | Implication |
| --- | --- | --- |

## Reference → Pattern → Principle → Product-specific implementation
| Reference | Pattern | Principle | Implementation |
| --- | --- | --- | --- |

## Flow model
 ```text
 Entry → task → result
 ```

## Adopt
- ...

## Avoid
- ...

## Open questions
 - ...
 ````

## Worked example: camera and pose-guide flow

### Research path used

The study started from Mobbin's iOS `Camera & Scanner` collection, then followed four `See similar` branches: Google Pay → Grab → Venmo → Revolut. Detailed screens from Apple Home, Wise, Snapchat, and Luma added contrast between accessory scanning, explicit import, creator capture, and a detected-result state. The collection showed 1,127 screens at the time of study.

### Sources

- [Mobbin iOS Camera & Scanner collection](https://mobbin.com/search/apps/ios?content_type=screens&sort=popularity&filter=screenPatterns.Camera+%26+Scanner)
- [Google Pay scanner](https://mobbin.com/screens/9020d962-0825-49b8-947f-6e0e6e36153e)
- [Apple Home accessory scanner](https://mobbin.com/screens/e25145c0-7af1-4c26-9103-fd71e6566afd)
- [Wise ID capture](https://mobbin.com/screens/926b23ed-df57-4906-82a9-98951363936e)
- [Snapchat creator camera](https://mobbin.com/screens/cc44df5b-bab7-443b-aa72-fcd820d8f9fa)
- [Luma QR check-in](https://mobbin.com/screens/a779f7d7-ecb5-4080-8bcd-b05cc92b30d4)

The similar sets also surfaced Grab, Venmo, Revolut, Setel, Cash App, Wise, KakaoTalk, Vivid, and World App.

### Extracted decisions

| Reference evidence | Pattern | Snap Pose decision |
| --- | --- | --- |
| Google Pay, Grab, Venmo, Revolut | Preview or scan target dominates; controls stay compact at the edges | Keep Camera full-bleed, with small Back and Tools surfaces inside full touch targets. |
| Venmo, Grab, Cash App | Image/gallery action can be icon-only | Make Choose guide an image icon with an accessible label. |
| Wise | Import becomes a peer action when it is equally important as scanning | Keep guide selection secondary because capturing the pose is the primary job. |
| Snapchat | Creator tools remain at the edge or in a compact bottom area | Open short camera settings in a bottom sheet. |
| Luma | Result actions appear contextually after detection | Show capture progress on the shutter; do not use a success toast. |

### Resulting flow

```text
Camera
  ├─ Choose a guide → dedicated guide screen → select → Camera
  ├─ Camera Tools → short bottom sheet → dismiss / Back → Camera
  └─ Capture → shutter disabled + inline spinner → Camera ready
```

The guide screen is a subordinate task, not a route through Home or the Home Poses list. Selection returns to Camera without leaving the picker in the Back stack. Zoom is represented as a real slider/progress control, and the busy shutter exposes `Saving photo` plus a hidden `Saving…` status.

## Quality checks

- Did the research include multiple products and at least one meaningful contrast?
- Did at least one `See similar` branch expand the initial collection?
- Can every adopted decision be traced to a reference and a principle?
- Does the flow explain entry, completion, Back, loading, and recovery?
- Are visual decisions translated into the product's own tokens and accessible controls?
- Are unsupported assumptions marked as open questions rather than presented as research findings?
