(function () { document.addEventListener('DOMContentLoaded', function () {
  const params = new URLSearchParams(location.search), intent = params.get('intent') || 'saved';
  const copy = {
    saved: 'View your saved poses.',
    account: 'Manage your account.',
    save: 'Save this pose.',
    try: 'Try this pose.'
  };
  document.getElementById('sign-in-copy').textContent = copy[intent] || copy.saved;
  const modal = document.getElementById('sign-in-modal'), live = document.getElementById('sign-in-live'), error = document.getElementById('sign-in-error');
  document.getElementById('google-sign-in').focus();
  document.addEventListener('keydown', function (event) { if (event.key === 'Escape') { modal.classList.remove('is-open'); modal.setAttribute('aria-hidden', 'true'); } });
  document.getElementById('google-sign-in').onclick = function () { if (params.get('state') === 'fail') { window.NBEmptyState.render(error, { action: { label: 'Try again', onClick: () => { const retry = new URL(location.href); retry.searchParams.delete('state'); location.href = retry.href; } }, copy: 'Try again to continue.', state: 'error', title: 'Sign-in failed' }); live.textContent = 'Sign-in failed'; return; } live.textContent = 'Signed in'; if (intent === 'saved') { location.href = 'saved-list.html'; return; } const destination = params.get('return') ? new URL(decodeURIComponent(params.get('return')), location.href) : new URL('pose-detail-saved.html?id=dancing&state=unsaved', location.href); destination.searchParams.delete('auth'); if (intent === 'save') destination.searchParams.set('state', 'saved'); location.href = destination.href; };
  function returnToContext() { location.href = params.get('return') ? decodeURIComponent(params.get('return')) : 'poses-list.html'; }
  document.querySelectorAll('[data-close-modal]').forEach(function (button) { button.addEventListener('click', returnToContext); });
  document.addEventListener('keydown', function (event) { if (event.key === 'Escape') returnToContext(); });
  document.getElementById('not-now').onclick = returnToContext;
}); })();
