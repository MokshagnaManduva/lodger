# Focused polish plan — 2026-09-16

Approved: replace the dumpling with the supplied sun emblem, occasionally tossed
and caught while standing idle and held during other actions. Use a 12×14 native
glyph, 20px arc and 1.2s action. Narrow walking and other leg poses, review shoulder
connections and transition seams, regenerate both direction previews, validate,
build the app and repeat isolated idle measurements. Update the project backlog.
Full turnaround, dangling perch and sound are deferred. See README/verification
for delivered behavior and evidence. The original plan below is historical.

# Klien: all declared animation scenarios

Approved direction: retain idle-v2 identity, 128px cells, 96px standing figure,
58px standing silhouette, locked 26-color palette, ground boundary y=120.
Energy target: <7 CPU seconds per idle hour; zero timers in quiescent states.

1. Use the saved full state blueprint as the scenario inventory: idle, walking,
   turning, perched, watching, startled, tipping_hat, held, falling, landing,
   sitting, sleeping, asleep, waking. Keep sound out of this artwork milestone.
2. Generate pose studies from the approved character using built-in imagegen.
   Author native frames from the approved sprite with local limb/pose edits,
   keeping a stable head. Keep cane and item editable as separate source layers.
3. Build explicit key poses and transitions: stepping feet; a brief turn;
   raised-hand hat touch and bow; recoil; suspended/kicking legs; tucked falling
   legs and cape; landing squash and recovery; seated legs; eye close/drowse;
   quiet sleep breathing; waking and standing. Do not substitute whole-sprite
   translation for these motions.
4. Export reusable frames, labeled contact sheets and looping nearest-neighbor
   GIFs for every scenario, plus a local HTML animation gallery. Record timings,
   prompts and authored anchors. Identify any remaining art limitations.
5. Build compact runtime atlases and alpha hit masks, then activate the completed
   state graph through pack data. Preserve the approved idle source and blueprint.
6. Verify every state/clip reference, palette, binary alpha, margins, stable
   contacts where appropriate, blink timing, leg/cape deformation, and loop seams.
   Build the app and run engine checks. Review animations at native/2x scales and
   measure idle against the updated <7s/hour target. No sound or distribution work.
