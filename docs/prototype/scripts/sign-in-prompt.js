(function () { document.addEventListener('DOMContentLoaded', function () {
  const params = new URLSearchParams(location.search), intent = params.get('intent') || 'saved';
  const copy = { saved: 'Sign in to view your saved poses.', save: 'Sign in to save poses to your account.', try: 'Sign in to try this pose.' };
  document.getElementById('sign-in-copy').textContent = copy[intent] || copy.saved;
  const modal = document.getElementById('sign-in-modal'), live = document.getElementById('sign-in-live'), error = document.getElementById('sign-in-error');
  document.getElementById('google-sign-in').focus();
  document.addEventListener('keydown', function (event) { if (event.key === 'Escape') { modal.classList.remove('is-open'); modal.setAttribute('aria-hidden', 'true'); } });
  document.getElementById('google-sign-in').onclick = function () { if (params.get('state') === 'fail') { error.innerHTML = '<strong>Sign-in failed</strong><p>Try again to continue.</p><button class="nb-btn nb-btn--white" type="button" id="retry-google">Retry</button>'; error.hidden = false; document.getElementById('retry-google').onclick = () => error.hidden = true; live.textContent = 'Sign-in failed'; return; } live.textContent = 'Signed in'; if (intent === 'saved') location.href = 'saved-list.html'; else location.href = params.get('return') ? decodeURIComponent(params.get('return')) : 'pose-detail-saved.html?id=dancing&state=saved'; };
  document.getElementById('not-now').onclick = function () { modal.setAttribute('aria-hidden', 'true'); live.textContent = 'Sign-in cancelled'; };
}); })();
