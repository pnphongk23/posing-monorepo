(function () {
  document.addEventListener('DOMContentLoaded', function () {
    const proto = window.PosePrototype, params = new URLSearchParams(location.search), state = params.get('state') || 'saved';
    const source = params.get('source') || 'saved', origin = params.get('origin') || source;
    const pose = proto && proto.getPoseByReference(params.get('id') || 'dancing', source === 'saved' ? 'community' : source);
    const content = document.getElementById('saved-detail-content'), unavailable = document.getElementById('saved-detail-state');
    const toggle = document.getElementById('saved-toggle'), tryBtn = document.getElementById('saved-try'), live = document.getElementById('saved-detail-live');
    const esc = proto ? proto.escapeHtml : String;
    const back = document.getElementById('detail-back'), sourceBadge = document.getElementById('saved-detail-source'), context = document.getElementById('saved-detail-context');
    const backDestination = origin === 'saved' || source === 'saved'
        ? { href: 'saved-list.html', label: 'Back to Saved' }
        : origin === 'search'
          ? { href: 'search.html' + (params.get('q') ? '?q=' + encodeURIComponent(params.get('q')) : ''), label: 'Back to Search' }
          : { href: 'poses-list.html?tab=community', label: 'Back to Community' };
    if (back) { back.href = backDestination.href; back.setAttribute('aria-label', backDestination.label); }
    function unavailableState() { content.hidden = true; unavailable.innerHTML = '<strong>Pose unavailable</strong><p>Pose này đã xoá hoặc đã ẩn.</p><button class="nb-btn nb-btn--pink nb-saved-readonly" type="button" disabled>Try Pose</button><button class="nb-btn nb-btn--white" type="button" id="detail-unavailable-back">' + backDestination.label + '</button>'; unavailable.hidden = false; document.getElementById('saved-detail-title').textContent = 'Unavailable'; document.getElementById('detail-unavailable-back').onclick = () => location.href = backDestination.href; }
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
    tryBtn.onclick = function () { if (params.get('auth') === 'guest') prompt('try'); else { live.textContent = 'Try Pose is ready in this prototype.'; } };
    paint();
    if (state === 'error') {
      unavailable.className = 'nb-state-message nb-state-message--error'; unavailable.innerHTML = '<strong>Couldn’t update Saved</strong><p>Your confirmed state is unchanged.</p><button class="nb-btn nb-btn--white" type="button" id="saved-retry">Retry</button>'; unavailable.hidden = false;
      document.getElementById('saved-retry').onclick = () => { location.href = 'pose-detail-saved.html?source=' + encodeURIComponent(params.get('source') || 'community') + '&id=' + encodeURIComponent(pose.id) + '&state=' + (saved ? 'saved' : 'unsaved'); };
    }
    if (state === 'pending-save' || state === 'pending-unsave') {
      toggle.disabled = true; toggle.innerHTML = '<span>' + (state === 'pending-save' ? 'Saving…' : 'Removing…') + '</span>'; live.textContent = state === 'pending-save' ? 'Saving…' : 'Removing…';
      setTimeout(() => { saved = state === 'pending-save'; toggle.disabled = false; toggle.innerHTML = '<svg aria-hidden="true"><use href="#icon-bookmark"></use></svg><span id="saved-toggle-label">' + (saved ? 'Saved' : 'Save') + '</span>'; paint(); live.textContent = saved ? 'Saved' : 'Removed from Saved'; }, 500);
    }
  });
})();
