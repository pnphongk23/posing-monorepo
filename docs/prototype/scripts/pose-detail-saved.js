(function () {
  document.addEventListener('DOMContentLoaded', function () {
    const proto = window.PosePrototype, params = new URLSearchParams(location.search), state = params.get('state') || 'saved';
    const source = params.get('source') || 'saved', origin = params.get('origin') || source;
    const pose = proto && proto.getPoseByReference(params.get('id') || 'dancing', source === 'saved' ? 'community' : source);
    const content = document.getElementById('saved-detail-content'), unavailable = document.getElementById('saved-detail-state');
    const toggle = document.getElementById('saved-toggle'), tryBtn = document.getElementById('saved-try'), live = document.getElementById('saved-detail-live');
    const esc = proto ? proto.escapeHtml : String;
    const back = document.getElementById('detail-back'), sourceBadge = document.getElementById('saved-detail-source'), context = document.getElementById('saved-detail-context');
      const searchOrigin = new URLSearchParams();
      if (params.get('q')) searchOrigin.set('q', params.get('q'));
      if (params.get('source') && source !== 'saved') searchOrigin.set('source', params.get('source'));
      const backDestination = origin === 'saved' || source === 'saved'
          ? { href: 'saved-list.html', label: 'Back to Saved' }
          : origin === 'search'
            ? { href: 'search.html' + (searchOrigin.toString() ? '?' + searchOrigin.toString() : ''), label: 'Back to Search' }
            : { href: 'poses-list.html?tab=community', label: 'Back to Community' };
    if (back) { back.href = backDestination.href; back.setAttribute('aria-label', backDestination.label); }
      function unavailableState() {
        content.hidden = true;
        window.NBEmptyState.render(unavailable, {
          action: {
            href: backDestination.href,
            label: backDestination.label
          },
          copy: 'This pose has been removed or hidden.',
          state: 'error',
          title: 'Pose unavailable'
        });
        document.getElementById('saved-detail-title').textContent = 'Unavailable';
      }
    if (state === 'unavailable' || !pose) { unavailableState(); return; }
    document.getElementById('saved-detail-title').textContent = pose.title; document.getElementById('saved-detail-name').textContent = pose.title; document.getElementById('saved-detail-art').innerHTML = pose.svg;
    const isSavedContext = origin === 'saved' || source === 'saved';
    sourceBadge.textContent = isSavedContext ? 'Saved' : 'Community';
    context.textContent = isSavedContext ? 'Saved · Community' : 'Published · Community';
    const meta = pose.metadata || {}; document.getElementById('saved-detail-meta').innerHTML = ['Author: ' + meta.author, 'Difficulty: ' + meta.difficulty, 'Saves: ' + meta.saves].filter(v => !v.endsWith('null')).map(v => '<span class="nb-tag nb-tag--pill" role="listitem">' + esc(v) + '</span>').join('');
    let saved = state !== 'unsaved' && state !== 'pending-save'; const readonly = state === 'offline';
    if (readonly) { document.getElementById('saved-detail-offline').hidden = false; toggle.disabled = true; tryBtn.disabled = true; toggle.classList.add('nb-saved-readonly'); }
    function paint() { toggle.classList.toggle('is-confirmed', saved); toggle.setAttribute('aria-label', saved ? 'Remove pose from Saved' : 'Save pose'); document.getElementById('saved-toggle-label').textContent = saved ? 'Saved' : 'Save'; }
    function prompt(intent) { location.href = 'sign-in-prompt.html?intent=' + intent + '&return=' + encodeURIComponent(location.href); }
    toggle.onclick = function () { if (readonly) return; if (params.get('auth') === 'guest') { prompt('save'); return; } const was = saved; toggle.disabled = true; toggle.innerHTML = '<span>…</span>'; live.textContent = was ? 'Removing…' : 'Saving…'; if (state === 'error') { toggle.disabled = false; toggle.innerHTML = '<svg aria-hidden="true"><use href="#icon-bookmark"></use></svg><span id="saved-toggle-label">' + (saved ? 'Saved' : 'Save') + '</span>'; live.textContent = 'Couldn’t update Saved. Retry.'; return; } setTimeout(() => { saved = !was; toggle.disabled = false; toggle.innerHTML = '<svg aria-hidden="true"><use href="#icon-bookmark"></use></svg><span id="saved-toggle-label">' + (saved ? 'Saved' : 'Save') + '</span>'; paint(); live.textContent = saved ? 'Saved' : 'Removed from Saved'; }, 350); };
    tryBtn.onclick = function () { if (params.get('auth') === 'guest') prompt('try'); else { live.textContent = 'Try pose is ready in this prototype.'; } };
      paint();
      if (state === 'error') {
        window.NBEmptyState.render(unavailable, {
          action: {
            label: 'Try again',
            onClick: () => { location.href = 'pose-detail-saved.html?source=' + encodeURIComponent(params.get('source') || 'community') + '&id=' + encodeURIComponent(pose.id) + '&state=' + (saved ? 'saved' : 'unsaved'); }
          },
          copy: 'Your confirmed state is unchanged.',
          state: 'error',
          title: 'Couldn’t update Saved'
        });
      }
    if (state === 'pending-save' || state === 'pending-unsave') {
      toggle.disabled = true; toggle.innerHTML = '<span>' + (state === 'pending-save' ? 'Saving…' : 'Removing…') + '</span>'; live.textContent = state === 'pending-save' ? 'Saving…' : 'Removing…';
      setTimeout(() => { saved = state === 'pending-save'; toggle.disabled = false; toggle.innerHTML = '<svg aria-hidden="true"><use href="#icon-bookmark"></use></svg><span id="saved-toggle-label">' + (saved ? 'Saved' : 'Save') + '</span>'; paint(); live.textContent = saved ? 'Saved' : 'Removed from Saved'; }, 500);
    }
  });
})();
