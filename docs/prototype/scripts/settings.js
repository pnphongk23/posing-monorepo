/* Settings screen interaction hooks. */
(function () {
  'use strict';

  var aboutSheet = document.getElementById('settings-about-sheet');
  var aboutTrigger = document.getElementById('settings-about-trigger');
  var iosDialog = document.getElementById('settings-ios-dialog');
  var cameraAccess = document.getElementById('settings-camera-access');
  var iosOpen = document.getElementById('settings-ios-open');
  var activeOverlay = null;
  var lastFocus = null;

  function focusableElements(root) {
    return Array.from(root.querySelectorAll(
      'button:not([disabled]), a[href], [tabindex]:not([tabindex="-1"])'
    ));
  }

  function openOverlay(overlay, trigger) {
    if (!overlay) return;
    if (activeOverlay && activeOverlay !== overlay) {
      closeOverlay(activeOverlay, false);
    }
    lastFocus = trigger || document.activeElement;
    activeOverlay = overlay;
    overlay.inert = false;
    overlay.classList.add('is-open');
    overlay.setAttribute('aria-hidden', 'false');
    var first = focusableElements(overlay)[0];
    if (first) first.focus();
  }

  function closeOverlay(overlay, restoreFocus) {
    if (!overlay) return;
    overlay.classList.remove('is-open');
    overlay.setAttribute('aria-hidden', 'true');
    overlay.inert = true;
    if (activeOverlay === overlay) activeOverlay = null;
    if (restoreFocus !== false && lastFocus && typeof lastFocus.focus === 'function') {
      lastFocus.focus();
    }
    lastFocus = null;
  }

  function bindCloseControls() {
    document.querySelectorAll('[data-settings-close]').forEach(function (button) {
      button.addEventListener('click', function () {
        var overlay = button.closest('.nb-settings-sheet, .nb-modal-overlay');
        closeOverlay(overlay, true);
      });
    });
  }

  if (aboutTrigger && aboutSheet) {
    aboutTrigger.addEventListener('click', function () {
      openOverlay(aboutSheet, aboutTrigger);
    });
  }

  if (cameraAccess && iosDialog) {
    cameraAccess.addEventListener('click', function () {
      openOverlay(iosDialog, cameraAccess);
    });
  }

  if (iosOpen) {
    iosOpen.addEventListener('click', function () {
      closeOverlay(iosDialog, true);
    });
  }

  document.addEventListener('keydown', function (event) {
    if (event.key !== 'Escape' || !activeOverlay) return;
    closeOverlay(activeOverlay, true);
  });

  bindCloseControls();
})();
