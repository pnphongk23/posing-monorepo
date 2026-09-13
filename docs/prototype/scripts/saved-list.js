(function () {
  document.addEventListener('DOMContentLoaded', function () {
    const proto = window.PosePrototype;
    const params = new URLSearchParams(window.location.search);
    const state = params.get('state') || 'ready';
    const all = (proto ? proto.getVisiblePoseFixtures() : []).filter(p => p.category === 'community' && p.visibility === 'published');
    const grid = document.getElementById('saved-grid');
    const message = document.getElementById('saved-state');
      const end = document.getElementById('saved-end');
      const offline = document.getElementById('saved-offline-banner');
      const scrollArea = document.getElementById('saved-scroll-area');
      const pullIndicator = document.getElementById('saved-pull-indicator');
      const pullIndicatorText = pullIndicator ? pullIndicator.querySelector('span') : null;
      const limit = Math.max(1, Number(params.get('limit')) || 20);
      const pullThreshold = 56;
      let pullStartY = null;
      let pullDistance = 0;
      let pulling = false;
      let refreshing = false;
    let page = Math.max(1, Number(params.get('page')) || 1);
    let loaded = [];
      const esc = proto ? proto.escapeHtml : value => String(value);

      function setMessage(kind, title, copy, actionLabel, action) {
        window.NBEmptyState.render(message, {
          action: actionLabel ? { label: actionLabel, onClick: action } : null,
          copy,
          state: kind,
          title
        });
      }
      function card(p, index) {
      const item = document.createElement('div'); item.className = 'nb-grid-pose-item';
        const detailState = state === 'offline-stale' ? 'offline' : 'saved';
        item.innerHTML = '<a class="nb-card nb-card--pose-grid nb-saved-card nb-card--aspect-' + ['tall','square','short'][index % 3] + ' u-w-full" href="pose-detail-saved.html?source=saved&id=' + encodeURIComponent(p.id) + '&state=' + detailState + '" aria-label="Saved pose, ' + esc(p.title) + '" style="text-decoration:none;color:inherit">' + p.svg + '<span class="nb-saved-card__badge" aria-hidden="true"><svg aria-hidden="true"><use href="#icon-bookmark"></use></svg></span></a><span class="nb-grid-pose-label">' + esc(p.title) + '</span>';
      return item;
    }
      function render() { grid.innerHTML = ''; loaded.forEach((p, i) => grid.appendChild(card(p, i))); grid.hidden = loaded.length === 0; grid.removeAttribute('aria-busy'); grid.dataset.page = page; grid.dataset.limit = limit; grid.dataset.total = all.length; }
      function retryInitial() { window.location.href = 'saved-list.html?state=ready&limit=' + limit; }
      function initial() {
          if (state === 'loading') { grid.innerHTML = ''; grid.hidden = true; grid.setAttribute('aria-busy', 'true'); setMessage('loading', 'Loading saved poses', 'Getting your saved collection ready.'); return; }
          if (state === 'error') { grid.hidden = true; setMessage('error', 'Couldn’t load saved poses', 'Check your connection and try again.', 'Try again', retryInitial); return; }
          if (state === 'offline-no-cache') { grid.hidden = true; setMessage('offline', 'Saved poses aren’t available offline', 'Reconnect to load your saved collection.', 'Try again', retryInitial); return; }
          if (state === 'empty') { grid.hidden = true; setMessage('empty', 'No saved poses yet', 'Save poses from Community to find them here.', 'Browse Community', () => { window.location.href = 'poses-list.html?tab=community'; }); return; }
        loaded = all.slice(0, Math.min(limit * page, all.length)); render();
          if (state === 'offline-stale') { offline.hidden = false; document.querySelectorAll('.nb-saved-card').forEach(a => a.classList.add('nb-saved-readonly')); }
        if (state === 'refresh-error') setMessage('warning', 'Couldn’t refresh', 'Showing your saved poses. Try again when you’re ready.', 'Retry', retryInitial);
        renderEnd();
      }
      function renderEnd() {
        end.innerHTML = ''; if (loaded.length >= all.length && !state.startsWith('load-more-')) return;
        if (state === 'load-more-loading' || state === 'load-more-error') {
          const stateElement = document.createElement('nb-empty-state');
          stateElement.className = 'nb-saved-end-state';
          end.appendChild(stateElement);
          if (state === 'load-more-loading') {
            window.NBEmptyState.render(stateElement, { state: 'loading', title: 'Loading more saved poses', copy: 'Getting the next poses ready.' });
          } else {
            window.NBEmptyState.render(stateElement, { state: 'error', title: 'Couldn’t load more saved poses', copy: 'Try again to continue.', action: { label: 'Try again', onClick: () => { page += 1; loaded = all.slice(0, Math.min(limit * page, all.length)); render(); renderEnd(); } } });
          }
          return;
        }
        const b = document.createElement('button'); b.className = 'nb-btn nb-btn--white'; b.textContent = 'Load more'; b.type = 'button'; b.addEventListener('click', () => { page += 1; loaded = all.slice(0, Math.min(limit * page, all.length)); render(); renderEnd(); }); end.appendChild(b);
      }
      function setPullState(mode, distance) {
        if (!scrollArea || !pullIndicator) return;
        const offset = Math.min(distance * 0.65, 36);
        scrollArea.style.setProperty('--nb-pull-offset', offset + 'px');
        scrollArea.style.setProperty('--nb-pull-content-offset', offset + 'px');
        scrollArea.classList.toggle('is-pulling', mode === 'pulling');
        scrollArea.classList.toggle('is-refreshing', mode === 'refreshing');
        pullIndicator.classList.toggle('is-pulling', mode === 'pulling');
        pullIndicator.classList.toggle('is-refreshing', mode === 'refreshing');
        pullIndicator.setAttribute('aria-hidden', mode === 'idle' ? 'true' : 'false');
        if (pullIndicatorText) pullIndicatorText.textContent = mode === 'refreshing' ? 'Refreshing saved poses…' : distance >= pullThreshold ? 'Release to refresh' : 'Pull to refresh';
      }
      function resetPull() {
        pullStartY = null;
        pullDistance = 0;
        pulling = false;
        setPullState('idle', 0);
      }
      function bindPullToRefresh() {
        if (!scrollArea || !pullIndicator) return;
        scrollArea.addEventListener('touchstart', event => {
          if (refreshing || event.touches.length !== 1 || scrollArea.scrollTop > 0) { resetPull(); return; }
          pullStartY = event.touches[0].clientY;
        }, { passive: true });
        scrollArea.addEventListener('touchmove', event => {
          if (refreshing || pullStartY === null || event.touches.length !== 1 || scrollArea.scrollTop > 0) return;
          pullDistance = event.touches[0].clientY - pullStartY;
          if (pullDistance <= 0) { resetPull(); return; }
          pulling = true;
          event.preventDefault();
          setPullState('pulling', pullDistance);
        }, { passive: false });
        scrollArea.addEventListener('touchend', () => {
          if (!pulling) { resetPull(); return; }
          if (pullDistance >= pullThreshold) {
            refreshing = true;
            setPullState('refreshing', pullThreshold);
            window.setTimeout(retryInitial, 250);
            return;
          }
          resetPull();
        }, { passive: true });
        scrollArea.addEventListener('touchcancel', resetPull, { passive: true });
      }
      bindPullToRefresh();
      initial();
  });
})();
