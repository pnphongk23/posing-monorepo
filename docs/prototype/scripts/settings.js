/* Settings screen prototype script. */
(function () {
  'use strict';

  // This surface is intentionally static: no auth, persistence, platform reads,
  // preference controls, or production navigation is implemented here.
  document.addEventListener('DOMContentLoaded', function () {
    const screen = document.getElementById('settings-screen');
    if (!screen) return;

    screen.dataset.prototypeState = 'static';
  });
})();
