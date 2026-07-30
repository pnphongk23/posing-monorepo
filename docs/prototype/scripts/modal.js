/* docs/prototype/scripts/modal.js */
function initModals() {
  // Dropdown Settings Popover (e.g. Camera Dots button)
  const dotsBtn = document.querySelector('.nb-camera-viewport__dots-btn');
  const dropdown = document.querySelector('.nb-dropdown');

  if (dotsBtn && dropdown) {
    dotsBtn.addEventListener('click', function(e) {
      e.stopPropagation();
      dropdown.classList.toggle('is-open');
      const isOpen = dropdown.classList.contains('is-open');
      dotsBtn.setAttribute('aria-expanded', isOpen);
    });

    // Close settings if click outside
    document.addEventListener('click', function(e) {
      if (!dropdown.contains(e.target) && !dotsBtn.contains(e.target)) {
        dropdown.classList.remove('is-open');
        dotsBtn.setAttribute('aria-expanded', 'false');
      }
    });

    // Support keyboard escape key closing
    document.addEventListener('keydown', function(e) {
      if (e.key === 'Escape') {
        dropdown.classList.remove('is-open');
        dotsBtn.setAttribute('aria-expanded', 'false');
      }
    });

    // Auto-open settings from URL (?settings=open)
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
