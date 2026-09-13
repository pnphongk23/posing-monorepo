/* docs/prototype/scripts/modal.js */
function initModals() {
  // Camera tools are a short anchored popup on the live camera.
  // Keep the dropdown fallback for the historical pose-overlay screen.
  const dotsBtn = document.getElementById('camera-settings-btn') || document.querySelector('.nb-camera-viewport__dots-btn');
  const settingsMenu = document.getElementById('camera-tools-menu');
  const dropdown = document.querySelector('.nb-dropdown');

  if (dotsBtn && settingsMenu) {
    const firstFocusable = () => settingsMenu.querySelector('button:not([disabled]), input:not([disabled])');

    function setSettingsOpen(isOpen) {
      settingsMenu.classList.toggle('is-open', isOpen);
      settingsMenu.hidden = !isOpen;
      settingsMenu.setAttribute('aria-hidden', String(!isOpen));
      dotsBtn.setAttribute('aria-expanded', String(isOpen));

      if (isOpen) {
        const firstControl = firstFocusable();
        if (firstControl) window.requestAnimationFrame(() => firstControl.focus());
      } else if (document.activeElement && settingsMenu.contains(document.activeElement)) {
        dotsBtn.focus({ preventScroll: true });
      }
    }

    dotsBtn.addEventListener('click', function(e) {
      e.stopPropagation();
      setSettingsOpen(settingsMenu.hidden);
    });

    document.addEventListener('click', function(e) {
      if (!settingsMenu.hidden && !settingsMenu.contains(e.target) && !dotsBtn.contains(e.target)) {
        setSettingsOpen(false);
      }
    });

    document.addEventListener('keydown', function(e) {
      if (e.key === 'Escape' && !settingsMenu.hidden) {
        e.preventDefault();
        setSettingsOpen(false);
      }
    });

    const params = new URLSearchParams(window.location.search);
    if (params.get('settings') === 'open') setSettingsOpen(true);
  } else if (dotsBtn && dropdown) {
    dotsBtn.addEventListener('click', function(e) {
      e.stopPropagation();
      dropdown.classList.toggle('is-open');
      const isOpen = dropdown.classList.contains('is-open');
      dotsBtn.setAttribute('aria-expanded', String(isOpen));
    });

    document.addEventListener('click', function(e) {
      if (!dropdown.contains(e.target) && !dotsBtn.contains(e.target)) {
        dropdown.classList.remove('is-open');
        dotsBtn.setAttribute('aria-expanded', 'false');
      }
    });

    document.addEventListener('keydown', function(e) {
      if (e.key === 'Escape') {
        dropdown.classList.remove('is-open');
        dotsBtn.setAttribute('aria-expanded', 'false');
      }
    });

    const params = new URLSearchParams(window.location.search);
    if (params.get('settings') === 'open') {
      dropdown.classList.add('is-open');
      dotsBtn.setAttribute('aria-expanded', 'true');
    }
  }

  // General Modal Overlays (if any exists)
  const openModalBtns = document.querySelectorAll('[data-open-modal]');
  const closeModalBtns = document.querySelectorAll('[data-close-modal]');

  openModalBtns.forEach(btn => {
    btn.addEventListener('click', function() {
      const modalId = this.getAttribute('data-open-modal');
      const targetModal = document.getElementById(modalId);
      if (targetModal) {
        targetModal.classList.add('is-open');
        targetModal.setAttribute('aria-hidden', 'false');
        // Simple a11y focus lock
        const closeBtn = targetModal.querySelector('[data-close-modal]');
        if (closeBtn) closeBtn.focus();
      }
    });
  });

  closeModalBtns.forEach(btn => {
    btn.addEventListener('click', function() {
      const targetModal = this.closest('.nb-modal-overlay');
      if (targetModal) {
        targetModal.classList.remove('is-open');
        targetModal.setAttribute('aria-hidden', 'true');
      }
    });
  });
}
window.initModals = initModals;
