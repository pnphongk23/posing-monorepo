/* docs/prototype/scripts/account.js */
(function () {
  document.addEventListener('DOMContentLoaded', function () {
    const signOutButton = document.getElementById('account-sign-out');
    const signInLink = document.getElementById('account-sign-in');
    const status = document.getElementById('account-status');
    const accountName = document.getElementById('account-name');
    const accountProvider = document.querySelector('.nb-account-profile__provider');
    const savedShortcut = document.querySelector('.nb-account-menu__item');

    if (!signOutButton || !signInLink || !status) return;

    signOutButton.addEventListener('click', function () {
      signOutButton.hidden = true;
      signInLink.hidden = false;
      if (accountName) accountName.textContent = 'Signed out';
      if (accountProvider) accountProvider.textContent = 'No active session';
      if (savedShortcut) savedShortcut.hidden = true;
        window.NBEmptyState.render(status, {
          copy: 'Sign in again to access your Saved poses.',
          state: 'success',
          title: 'Signed out'
        });
    });
  });
})();
