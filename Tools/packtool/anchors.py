"""packtool anchors - author per-frame anchors against a live drift trace.

Anchors are the one thing in the pipeline no tool can produce for you, and the
reference audit showed exactly what happens when they are inferred instead of
authored: the floating item's anchor drifted ~8 points of figure height between
cells that were meant to be the same character.

So the picker's whole point is that it draws the anchor's path across every frame
while you place them, and shows the per-frame jump the linter will later measure.
Drift becomes visible at authoring time instead of in a review.

Editor-agnostic by design: it takes a PNG frame strip, so any editor works.
"""
from __future__ import annotations

import json
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

PAGE = r"""<!doctype html><meta charset=utf-8><title>packtool anchors</title>
<style>
:root{--bg:#17171a;--panel:#212127;--line:#33333c;--fg:#e8e8ea;--dim:#8a8a95;
      --ok:#6fbf73;--warn:#e0a33e;--bad:#e05a4f;--sel:#5aa9e0}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);
     font:13px/1.5 ui-monospace,SFMono-Regular,Menlo,monospace;display:flex;height:100vh}
#main{flex:1;display:flex;flex-direction:column;min-width:0}
#stage{flex:1;display:grid;place-items:center;overflow:auto;padding:16px}
canvas{image-rendering:pixelated;background:#fafaf8;box-shadow:0 0 0 1px var(--line)}
#strip{display:flex;gap:6px;padding:10px;overflow-x:auto;border-top:1px solid var(--line);
       background:var(--panel)}
#strip canvas{cursor:pointer;box-shadow:0 0 0 1px var(--line)}
#strip canvas.on{box-shadow:0 0 0 2px var(--sel)}
aside{width:290px;border-left:1px solid var(--line);background:var(--panel);
      padding:14px;overflow-y:auto;display:flex;flex-direction:column;gap:14px}
h2{font-size:11px;letter-spacing:.08em;text-transform:uppercase;color:var(--dim);margin:0}
.a{padding:8px;border:1px solid var(--line);border-radius:5px;cursor:pointer}
.a.on{border-color:var(--sel);background:#2a3540}
.a .n{display:flex;justify-content:space-between}
.a .c{color:var(--dim);font-size:12px}
.jump{font-size:12px}
.ok{color:var(--ok)}.warn{color:var(--warn)}.bad{color:var(--bad)}
button{width:100%;padding:9px;background:var(--sel);color:#08121a;border:0;border-radius:5px;
       font:inherit;font-weight:600;cursor:pointer}
button.sec{background:#33333c;color:var(--fg)}
kbd{background:#33333c;border-radius:3px;padding:0 4px}
#msg{min-height:18px;color:var(--dim)}
label{display:flex;justify-content:space-between;align-items:center;color:var(--dim)}
input[type=checkbox]{accent-color:var(--sel)}
</style>
<div id=main>
  <div id=stage><canvas id=c></canvas></div>
  <div id=strip></div>
</div>
<aside>
  <div><h2>frame</h2><div id=fpos></div></div>
  <div><h2>anchors</h2><div id=list></div></div>
  <div><h2>drift</h2><div id=drift class=jump></div></div>
  <div><h2>view</h2>
    <label>trace across frames <input type=checkbox id=trace checked></label>
    <label>ghost other frames <input type=checkbox id=ghost checked></label>
  </div>
  <div id=msg></div>
  <button id=save>Save anchors.json</button>
  <button class=sec id=clear>Clear this anchor on this frame</button>
  <div style="color:var(--dim);font-size:12px">
    <kbd>&larr;</kbd><kbd>&rarr;</kbd> frame &middot; <kbd>1</kbd>..<kbd>9</kbd> anchor<br>
    click to place &middot; arrows+<kbd>shift</kbd> nudge<br>
    <kbd>cmd</kbd>+<kbd>s</kbd> save
  </div>
</aside>
<script>
const CFG = __CFG__;
const Z = CFG.zoom, CS = CFG.cell;
let frame = 0, anchor = CFG.anchors[0];
let data = CFG.existing || {};                 // {anchorName: {frameIndex: {x,y}}}
const img = new Image(); img.src = CFG.strip + '?v=' + Date.now();

const c = document.getElementById('c'), g = c.getContext('2d');
c.width = CS * Z; c.height = CS * Z;

function at(a, f){ return (data[a] || {})[f] || null; }
function set(a, f, p){ (data[a] = data[a] || {})[f] = p; draw(); }

function draw(){
  g.imageSmoothingEnabled = false;
  g.clearRect(0,0,c.width,c.height);
  g.fillStyle = '#fafaf8'; g.fillRect(0,0,c.width,c.height);
  g.drawImage(img, frame*CS, 0, CS, CS, 0, 0, CS*Z, CS*Z);

  // ground line from stage.ground, so registration is visible while authoring
  if (CFG.ground != null){
    g.strokeStyle = 'rgba(90,169,224,.55)'; g.lineWidth = 1;
    g.beginPath(); g.moveTo(0, CFG.ground*Z+.5); g.lineTo(c.width, CFG.ground*Z+.5); g.stroke();
  }

  const showTrace = document.getElementById('trace').checked;
  const showGhost = document.getElementById('ghost').checked;

  for (const a of CFG.anchors){
    const pts = [];
    for (let f=0; f<CFG.frames; f++){ const p = at(a,f); if (p) pts.push([f,p]); }
    const cur = a === anchor;
    // the point of this tool: the path across every frame, drawn while you author
    if (showTrace && pts.length > 1){
      g.strokeStyle = cur ? 'rgba(224,163,62,.9)' : 'rgba(138,138,149,.35)';
      g.lineWidth = cur ? 2 : 1;
      g.beginPath();
      pts.forEach(([,p],i)=>{ const x=(p.x+.5)*Z, y=(p.y+.5)*Z;
        i ? g.lineTo(x,y) : g.moveTo(x,y); });
      g.stroke();
    }
    if (showGhost){
      for (const [f,p] of pts){ if (f === frame) continue;
        g.fillStyle = cur ? 'rgba(224,163,62,.28)' : 'rgba(138,138,149,.16)';
        g.beginPath(); g.arc((p.x+.5)*Z,(p.y+.5)*Z, cur?4:3, 0, 7); g.fill(); }
    }
    const p = at(a, frame); if (!p) continue;
    const x=(p.x+.5)*Z, y=(p.y+.5)*Z;
    g.strokeStyle = cur ? '#e0a33e' : '#8a8a95'; g.lineWidth = cur ? 2 : 1;
    g.beginPath(); g.moveTo(x-9,y); g.lineTo(x+9,y); g.moveTo(x,y-9); g.lineTo(x,y+9); g.stroke();
    g.beginPath(); g.arc(x,y,5,0,7); g.stroke();
    if (cur){ g.fillStyle='#e0a33e'; g.font='11px monospace';
              g.fillText(a, x+11, y-7); }
  }
  side();
}

function side(){
  document.getElementById('fpos').textContent = `${frame+1} / ${CFG.frames}`;
  document.getElementById('list').innerHTML = CFG.anchors.map((a,i)=>{
    const p = at(a, frame);
    return `<div class="a ${a===anchor?'on':''}" data-a="${a}">
      <div class=n><span>${i+1}. ${a}</span><span class=c>${p?`${p.x},${p.y}`:'—'}</span></div>
    </div>`;}).join('');
  document.querySelectorAll('.a').forEach(e=>e.onclick=()=>{ anchor=e.dataset.a; draw(); });

  // live readout of exactly what packtool lint will measure later
  const rows = CFG.anchors.map(a=>{
    let worst = 0, gaps = 0, at_ = null;
    for (let f=0; f<CFG.frames; f++){
      const p = at(a,f); if (!p){ gaps++; at_=null; continue; }
      if (at_){ const d = Math.max(Math.abs(p.x-at_.x), Math.abs(p.y-at_.y));
                if (d > worst) worst = d; }
      at_ = p;
    }
    const cls = gaps ? 'bad' : worst > CFG.limit ? 'warn' : 'ok';
    const note = gaps ? `${gaps} frame${gaps>1?'s':''} unset` : `max jump ${worst}px`;
    return `<div class="${cls}">${a}: ${note}</div>`;
  });
  document.getElementById('drift').innerHTML = rows.join('') +
    `<div style="color:var(--dim);margin-top:6px">limit ${CFG.limit}px</div>`;
  document.querySelectorAll('#strip canvas').forEach((e,i)=>
    e.classList.toggle('on', i===frame));
}

c.onclick = e => {
  const r = c.getBoundingClientRect();
  set(anchor, frame, { x: Math.floor((e.clientX-r.left)/Z), y: Math.floor((e.clientY-r.top)/Z) });
};

addEventListener('keydown', e => {
  if ((e.metaKey||e.ctrlKey) && e.key === 's'){ e.preventDefault(); save(); return; }
  const p = at(anchor, frame);
  if (e.shiftKey && p && e.key.startsWith('Arrow')){
    e.preventDefault();
    const d = {ArrowLeft:[-1,0],ArrowRight:[1,0],ArrowUp:[0,-1],ArrowDown:[0,1]}[e.key];
    if (d) set(anchor, frame, {x:p.x+d[0], y:p.y+d[1]});
    return;
  }
  if (e.key === 'ArrowLeft'){ frame = (frame-1+CFG.frames)%CFG.frames; draw(); }
  if (e.key === 'ArrowRight'){ frame = (frame+1)%CFG.frames; draw(); }
  const n = parseInt(e.key,10);
  if (n >= 1 && n <= CFG.anchors.length){ anchor = CFG.anchors[n-1]; draw(); }
});

document.getElementById('trace').onchange = draw;
document.getElementById('ghost').onchange = draw;
document.getElementById('clear').onclick = () => {
  if (data[anchor]) delete data[anchor][frame];
  draw();
};

function save(){
  fetch('/save', {method:'POST', headers:{'content-type':'application/json'},
                  body: JSON.stringify({anchors: data})})
    .then(r=>r.text()).then(t=>{ document.getElementById('msg').textContent = t; })
    .catch(e=>{ document.getElementById('msg').textContent = 'save failed: ' + e; });
}
document.getElementById('save').onclick = save;

img.onload = () => {
  const s = document.getElementById('strip');
  for (let f=0; f<CFG.frames; f++){
    const t = document.createElement('canvas'); t.width = t.height = CS*2;
    const tg = t.getContext('2d'); tg.imageSmoothingEnabled = false;
    tg.fillStyle = '#fafaf8'; tg.fillRect(0,0,CS*2,CS*2);
    tg.drawImage(img, f*CS, 0, CS, CS, 0, 0, CS*2, CS*2);
    t.onclick = () => { frame = f; draw(); };
    s.appendChild(t);
  }
  draw();
};
</script>
"""


def serve(pack: Path, strip: Path, cell: int, anchors: list[str],
          ground: int | None, limit: float, port: int, open_browser: bool = True) -> None:
    frames = _frame_count(strip, cell)
    out = pack / "anchors.json"
    existing = {}
    if out.exists():
        existing = json.loads(out.read_text()).get("anchors", {})
        existing = {a: {int(k): v for k, v in fr.items()} for a, fr in existing.items()}

    cfg = {"strip": "/strip.png", "cell": cell, "frames": frames, "anchors": anchors,
           "zoom": max(2, min(10, 640 // cell)), "ground": ground, "limit": limit,
           "existing": existing}
    page = PAGE.replace("__CFG__", json.dumps(cfg))

    class H(BaseHTTPRequestHandler):
        def log_message(self, *a):  # quiet
            pass

        def do_GET(self):
            path = urlparse(self.path).path
            if path == "/strip.png":
                body, ctype = strip.read_bytes(), "image/png"
            else:
                body, ctype = page.encode(), "text/html; charset=utf-8"
            self.send_response(200)
            self.send_header("content-type", ctype)
            self.send_header("content-length", str(len(body)))
            self.send_header("cache-control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def do_POST(self):
            n = int(self.headers.get("content-length", 0))
            payload = json.loads(self.rfile.read(n) or b"{}")
            doc = {
                "_comment": "Authored by packtool anchors. Per-frame anchor points in "
                            "cell coordinates. Never inferred from art.",
                "strip": strip.name, "cell": cell, "frames": frames,
                "anchors": payload.get("anchors", {}),
            }
            out.write_text(json.dumps(doc, indent=2, sort_keys=True) + "\n")
            placed = sum(len(v) for v in doc["anchors"].values())
            msg = f"saved {out.name}: {placed} points across {frames} frames"
            print(f"  {msg}")
            body = msg.encode()
            self.send_response(200)
            self.send_header("content-type", "text/plain; charset=utf-8")
            self.send_header("content-length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

    srv = ThreadingHTTPServer(("127.0.0.1", port), H)
    url = f"http://127.0.0.1:{port}/"
    print(f"anchor picker: {url}")
    print(f"  strip   : {strip}  ({frames} frames of {cell}x{cell})")
    print(f"  anchors : {', '.join(anchors)}")
    print(f"  writes  : {out}")
    print("  ctrl-c to stop")
    if open_browser:
        webbrowser.open(url)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\nstopped")


def _frame_count(strip: Path, cell: int) -> int:
    from PIL import Image
    w, h = Image.open(strip).size
    if h != cell or w % cell:
        raise SystemExit(f"strip {strip.name} is {w}x{h}; expected height {cell} "
                         f"and a width that is a multiple of {cell}")
    return w // cell
