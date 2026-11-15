# Norn animation polish · v0.3.0

Built-in imagegen artwork generated on 2026-09-25, using the original
`../runtime-v1/lifecycle-sheet.png` as the identity/style reference. Sources are
retained with true alpha; the existing compiler performs nearest-neighbor
registration, alpha thresholding and mapping to the original shared palette.

| Source | Runtime use | Prompt |
| --- | --- | --- |
| [walk-sheet.png](walk-sheet.png) | Four selected contact/passing poses, 0.72 s loop | [Initial](walk-prompt.txt), [final edit](walk-correction-3.txt) |
| [greet-sheet.png](greet-sheet.png) | Stow flask, wave, retrieve; 13 timed frames, 2.30 s | [Greeting](greet-prompt.txt) |
| [sit-sheet.png](sit-sheet.png) | Sit in 1.09 s; stand in 1.20 s; seated reading/blink | [Sitting](sit-prompt.txt) |

The walk generator repeatedly favored the same leading foot. The retained final
sheet has a useful opposite raised boot in cell 5. The runtime selects cells
0, 2, 1, 5; the other two drawings are retained for review, not played. Earlier
correction prompts and `walk-draft.png` record the iteration. This is a stylized
four-key walk, not a six-key biomechanically complete gait.

Edit `*-registration.json` for crop rectangles, scale and placement. The sitting
sheet needs a top-row crop ending at y=540 and a lower-row start at y=550;
uniform halves would cut the upper flask and leak it into a lower cell. Each
grounded runtime silhouette ends at y=114. Registration is authored data, not
runtime ground detection.

The greeting and sitting pages each contain six new drawings and three complete
canonical body cells. `bodyCell` references reuse source cells 0, 10 and 11;
only neutral is currently needed in these clips, while the two seated cells
remain available for comparison. There are 58 stored cells overall, including
six copied canonical cells. No new engine behavior or states were introduced.

Greeting starts/ends at canonical neutral. Sit ends on the exact reading frame;
stand begins there and reverses the sit poses before returning to neutral.
Reading uses the new seated open/closed-eye pair. The original idle, inspection,
hover, landing, sleep, held and falling drawings remain in use.

The root, flask and book are baked into the silhouettes. Within-sheet continuity
and ordinary sequence boundaries are improved, but generated shape variation and
pose jumps on arbitrary interrupts remain. This pass does not certify energy or
full desktop input behavior. See [verification.md](verification.md).
