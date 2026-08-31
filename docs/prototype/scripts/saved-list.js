(function () {
  document.addEventListener('DOMContentLoaded', function () {
    const proto = window.PosePrototype;
    const params = new URLSearchParams(window.location.search);
    const state = params.get('state') || 'ready';
    const all = (proto ? proto.getVisiblePoseFixtures() : []).filter(p => p.category === 'community' && p.visibility === 'published');
    const grid = document.getElementById('saved-grid');
    const message = document.getElementById('saved-state');
    const end = document.getElementById('saved-end');
    const count = document.getElementById('saved-count');
    const offline = document.getElementById('saved-offline-banner');
    const limit = Math.max(1, Number(params.get('limit')) || 20);
    let page = Math.max(1, Number(params.get('page')) || 1);
    let loaded = [];
    const esc = proto ? proto.escapeHtml : value => String(value);

    function setMessage(kind, title, copy, actionLabel, action) {
      message.className = 'nb-state-message nb-state-message--' + kind;
      message.innerHTML = '<strong>' + esc(title) + '</strong><p>' + esc(copy) + '</p>';
      if (actionLabel) { const btn = document.createElement('button'); btn.className = 'nb-btn nb-btn--white'; btn.type = 'button'; btn.textContent = actionLabel; btn.addEventListener('click', action); message.appendChild(btn); }
      message.hidden = false;
    }
    function clearMessage() { message.hidden = true; message.innerHTML = ''; }
    function card(p, index) {
      const item = document.createElement('div'); item.className = 'nb-grid-pose-item';
        const detailState = state === 'offline-stale' ? 'offline' : 'saved';
        item.innerHTML = '<a class="nb-card nb-card--pose-grid nb-saved-card nb-card--aspect-' + ['tall','short','square'][index % 3] + ' u-w-full" href="pose-detail-saved.html?source=saved&id=' + encodeURIComponent(p.id) + '&state=' + detailState + '" aria-label="Saved pose, ' + esc(p.title) + '" style="text-decoration:none;color:inherit">' + p.svg + '<span class="nb-saved-card__badge" aria-hidden="true"><svg aria-hidden="true"><use href="#icon-bookmark"></use></svg></span></a><span class="nb-grid-pose-label">' + esc(p.title) + '</span>';
      return item;
    }
    function render() { grid.innerHTML = ''; loaded.forEach((p, i) => grid.appendChild(card(p, i))); grid.hidden = loaded.length === 0; count.hidden = false; count.textContent = loaded.length + ' saved poses'; grid.dataset.page = page; grid.dataset.limit = limit; grid.dataset.total = all.length; }
    function retryInitial() { window.location.href = 'saved-list.html?state=ready&limit=' + limit; }
    function initial() {
      if (state === 'loading') { count.hidden = true; setMessage('loading', 'Loading saved poses', 'Hang on while we load your collection.'); grid.innerHTML = '<div class="nb-pose-loading" role="status">Loading saved poses…</div>'; return; }
      if (state === 'error') { count.hidden = true; setMessage('error', 'Unable to load saved poses', 'Something went wrong. Try again.', 'Retry', retryInitial); return; }
      if (state === 'offline-no-cache') { count.hidden = true; setMessage('error', 'Saved poses unavailable offline', 'Reconnect to load your saved collection.', 'Try again', retryInitial); return; }
      if (state === 'empty') { count.hidden = true; setMessage('empty', 'No saved poses yet', 'Save poses from Community to find them here.', 'Browse Community', () => { window.location.href = 'poses-list.html?tab=community'; }); return; }
      loaded = all.slice(0, Math.min(limit * page, all.length)); render();
        if (state === 'offline-stale') { offline.hidden = false; document.querySelectorAll('.nb-saved-card').forEach(a => a.classList.add('nb-saved-readonly')); }
      if (state === 'refresh-error') setMessage('error', 'Couldn’t refresh', 'Showing your saved poses. Try again when you’re ready.', 'Retry', retryInitial);
      renderEnd();
    }
    function renderEnd() {
      end.innerHTML = ''; if (loaded.length >= all.length && !state.startsWith('load-more-')) return;
      if (state === 'load-more-loading') { end.innerHTML = '<div class="nb-pose-loading" role="status">Loading more saved poses…</div>'; return; }
      if (state === 'load-more-error') { const p = document.createElement('p'); p.textContent = 'Couldn’t load more saved poses.'; const b = document.createElement('button'); b.className = 'nb-btn nb-btn--white'; b.textContent = 'Retry'; b.type = 'button'; b.addEventListener('click', () => { page += 1; loaded = all.slice(0, Math.min(limit * page, all.length)); render(); renderEnd(); }); end.append(p, b); return; }
      const b = document.createElement('button'); b.className = 'nb-btn nb-btn--white'; b.textContent = 'Load more'; b.type = 'button'; b.addEventListener('click', () => { page += 1; loaded = all.slice(0, Math.min(limit * page, all.length)); render(); renderEnd(); }); end.appendChild(b);
    }
    document.getElementById('saved-refresh').addEventListener('click', () => { window.location.href = 'saved-list.html?state=refresh-error'; });
    initial();
  });
})();
