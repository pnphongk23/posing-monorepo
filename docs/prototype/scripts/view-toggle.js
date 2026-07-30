/* docs/prototype/scripts/view-toggle.js */
function initViewToggle() {
  const toggleBtns = document.querySelectorAll('.nb-view-toggle__btn');
  const targetGrid = document.getElementById('gallery-grid');

  if (toggleBtns.length > 0 && targetGrid) {
    // Initialize aria-pressed states based on is-active class
    toggleBtns.forEach(btn => {
      const isActive = btn.classList.contains('is-active');
      btn.setAttribute('aria-pressed', isActive ? 'true' : 'false');
    });

    toggleBtns.forEach(btn => {
      btn.addEventListener('click', function() {
        // Clear active classes and aria-pressed states from sibling buttons
        toggleBtns.forEach(b => {
          b.classList.remove('is-active');
          b.setAttribute('aria-pressed', 'false');
        });
        this.classList.add('is-active');
        this.setAttribute('aria-pressed', 'true');

        const viewType = this.getAttribute('data-view');
        if (viewType === 'grid') {
          targetGrid.classList.add('nb-grid--2col');
          targetGrid.classList.remove('nb-grid--list'); // List layout helper style
        } else if (viewType === 'list') {
          targetGrid.classList.remove('nb-grid--2col');
          targetGrid.classList.add('nb-grid--list');
        }
      });
    });
  }
}
window.initViewToggle = initViewToggle;
