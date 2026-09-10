/* docs/prototype/scripts/modal.js */
function initModals() {
  // Camera tools use a short bottom sheet on the redesigned live camera.
  // Keep the dropdown fallback for the historical pose-overlay screen.
  const dotsBtn = document.getElementById('camera-settings-btn') || document.querySelector('.nb-camera-viewport__dots-btn');
  const settingsSheet = document.getElementById('camera-settings-sheet');
  const dropdown = document.querySelector('.nb-dropdown');

  if (dotsBtn && settingsSheet) {
    const closeButtons = settingsSheet.querySelectorAll('[data-close-camera-settings]');
    const closeButton = settingsSheet.querySelector('.nb-camera-settings-panel [data-close-camera-settings]');

    function setSettingsOpen(isOpen) {
      settingsSheet.classList.toggle('is-open', isOpen);
      settingsSheet.hidden = !isOpen;
      settingsSheet.setAttribute('aria-hidden', String(!isOpen));
      dotsBtn.setAttribute('aria-expanded', String(isOpen));

      if (isOpen && closeButton) {
        window.requestAnimationFrame(() => closeButton.focus());
      } else if (!isOpen) {
        dotsBtn.focus();
      }
    }

    dotsBtn.addEventListener('click', function(e) {
      e.stopPropagation();
      setSettingsOpen(settingsSheet.hidden);
    });

    closeButtons.forEach(button => {
      button.addEventListener('click', function() {
        setSettingsOpen(false);
      });
    });

    document.addEventListener('keydown', function(e) {
      if (e.key === 'Escape' && !settingsSheet.hidden) {
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
