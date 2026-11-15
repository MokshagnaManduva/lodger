# Historical implementation note: render-server locomotion

This plan is complete and retained as an engineering record. It is not the current backlog;
see [current status](../left.md).

Walking resolves one bounded segment up front, resizes the host window once, and animates the
host layer in Core Animation. The engine does not move the window on every frame and does not
start a display link for a normal walk. A walk interruption resolves the interpolated position,
removes the animation, and returns to the normal pet-sized window.

The implementation was accepted because it preserves hit testing, caps the transparent travel
corridor, keeps child attachments relative to the host, and leaves falling/dragging as the only
short-lived actively integrated paths. The render-server proof is recorded in the project
documentation and exercised by the engine tests.

Remaining measurements—especially WindowServer overhead and whole-system power—belong to the
[energy protocol](energy-protocol.md), not to this historical design note.
