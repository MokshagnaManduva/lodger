/* Local-only clip preview, shared by the archived studies and runtime atlas. */
(() => {
  'use strict';
  const drafts = window.NORN_DRAFTS;
  const gallery = document.querySelector('#gallery');
  const toggleAll = document.querySelector('#toggle-all');
  const status = document.querySelector('#load-status');
  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  let speed = 1;
  let loaded = 0;
  let failed = 0;
  let request = 0;
  let previous = 0;
  const studies = [];

  function syncGlobalButton() {
    toggleAll.textContent = studies.some(s => s.playing) ? 'Pause all' : 'Play all';
  }
  function sync(study) {
    study.play.textContent = study.playing ? 'Pause' : 'Play';
    study.play.setAttribute('aria-label', `${study.playing ? 'Pause' : 'Play'} ${study.draft.title}`);
    study.counter.textContent = `${String(study.frame + 1).padStart(2, '0')} / ${String(study.draft.frames.length).padStart(2, '0')}`;
    study.scrubber.value = study.frame;
    syncGlobalButton();
  }
  function draw(study) {
    if (!study.ready) return;
    const { image, context, canvas, draft, frame } = study;
    const width = image.naturalWidth / draft.columns;
    const height = image.naturalHeight / draft.rows;
    const cell = draft.cells ? draft.cells[frame] : frame;
    const col = cell % draft.columns;
    const row = Math.floor(cell / draft.columns);
    context.clearRect(0, 0, canvas.width, canvas.height);
    context.imageSmoothingEnabled = false;
    context.drawImage(image, col * width, row * height, width, height, 0, 0, canvas.width, canvas.height);
    sync(study);
  }
  function schedule() {
    if (!request && !document.hidden && studies.some(s => s.ready && s.playing)) {
      request = requestAnimationFrame(tick);
    }
  }
  function tick(now) {
    request = 0;
    const elapsed = previous ? Math.min(now - previous, 100) : 0;
    previous = now;
    for (const study of studies) {
      if (!study.ready || !study.playing) continue;
      study.elapsed += elapsed * speed;
      let changed = false;
      while (study.elapsed >= study.draft.frames[study.frame]) {
        study.elapsed -= study.draft.frames[study.frame];
        study.frame = (study.frame + 1) % study.draft.frames.length;
        changed = true;
      }
      if (changed) draw(study);
    }
    schedule();
    if (!request) previous = 0;
  }
  function setPlaying(study, playing) {
    study.playing = playing;
    sync(study);
    schedule();
  }
  function reportLoading() {
    status.textContent = failed ? `${loaded} ready · ${failed} failed to load` : `${loaded} / ${drafts.length} studies ready`;
  }

  drafts.forEach((draft, index) => {
    const card = document.createElement('article');
    card.className = 'card';
    card.dataset.study = draft.id;
    card.id = `clip-${draft.id}`;
    card.innerHTML = `
      <div class="card-top"><span>STUDY ${String(index + 1).padStart(2, '0')}</span><span class="category">${draft.category.toUpperCase()}</span></div>
      <div class="stage" data-background="paper"><canvas width="${draft.nativeCell || 512}" height="${draft.nativeCell || 512}" role="img" aria-label="${draft.title} animation preview">${draft.description}</canvas></div>
      <div class="card-content"><h3>${draft.title}</h3><p class="description">${draft.description}</p>
        <div class="playback"><button class="play" type="button" disabled>Play</button><button class="step" type="button" aria-label="Next frame of ${draft.title}" disabled>Step →</button><output class="frame-count" aria-label="Current frame">01 / 06</output></div>
        <input class="scrubber" type="range" min="0" max="${draft.frames.length - 1}" step="1" value="0" aria-label="Frame for ${draft.title}" disabled>
        <div class="card-meta"><span>${draft.frames.length} FRAMES · ${(draft.duration / 1000).toFixed(2)}s ${draft.runtimeLoop === 'none' ? 'ACTION · REPLAY' : 'LOOP'}</span><a href="${draft.src}" target="_blank" rel="noopener">Sprite sheet ↗</a></div>
      </div>`;
    gallery.append(card);
    const canvas = card.querySelector('canvas');
    const study = { draft, canvas, context: canvas.getContext('2d'), image: new Image(), frame: 0, elapsed: 0, ready: false, playing: !reducedMotion.matches, play: card.querySelector('.play'), counter: card.querySelector('.frame-count'), scrubber: card.querySelector('.scrubber') };
    studies.push(study);
    study.play.addEventListener('click', () => setPlaying(study, !study.playing));
    card.querySelector('.step').addEventListener('click', () => {
      setPlaying(study, false);
      study.frame = (study.frame + 1) % draft.frames.length;
      study.elapsed = 0;
      draw(study);
    });
    study.scrubber.addEventListener('input', () => {
      const selectedFrame = Number(study.scrubber.value);
      setPlaying(study, false);
      study.frame = selectedFrame;
      study.elapsed = 0;
      draw(study);
    });
    study.image.onload = () => {
      study.ready = true;
      loaded++;
      card.querySelectorAll('button,input').forEach(control => { control.disabled = false; });
      draw(study);
      reportLoading();
      schedule();
    };
    study.image.onerror = () => {
      failed++;
      study.playing = false;
      const message = document.createElement('p');
      message.className = 'load-error';
      message.textContent = 'Sheet unavailable. Keep the drafts folder beside this gallery.';
      card.querySelector('.stage').append(message);
      syncGlobalButton();
      reportLoading();
    };
    study.image.src = draft.src;
    sync(study);
  });
  toggleAll.addEventListener('click', () => {
    const playing = !studies.some(study => study.playing);
    studies.forEach(study => { if (study.ready) setPlaying(study, playing); });
  });
  document.querySelector('#speed').addEventListener('change', event => { speed = Number(event.target.value); });
  document.querySelector('#background').addEventListener('change', event => {
    document.querySelectorAll('.stage').forEach(stage => { stage.dataset.background = event.target.value; });
  });
  document.addEventListener('visibilitychange', () => {
    if (request) cancelAnimationFrame(request);
    request = 0;
    previous = 0;
    if (!document.hidden) schedule();
  });
  reducedMotion.addEventListener('change', event => {
    if (event.matches) studies.forEach(study => setPlaying(study, false));
  });
})();
