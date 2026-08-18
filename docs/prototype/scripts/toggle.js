/* docs/prototype/scripts/toggle.js */
function initToggles() {
  // Grid Overlay Toggle on Camera view
  const gridSwitch = document.getElementById('grid-switch');
  const gridOverlay = document.getElementById('camera-grid');

  if (gridSwitch && gridOverlay) {
    // Set initial state based on checkbox
    if (gridSwitch.checked) {
      gridOverlay.classList.remove('is-hidden');
    } else {
      gridOverlay.classList.add('is-hidden');
    }

    gridSwitch.addEventListener('change', function(e) {
      if (e.target.checked) {
        gridOverlay.classList.remove('is-hidden');
      } else {
        gridOverlay.classList.add('is-hidden');
      }
    });
  }

  const zoomBtn = document.getElementById('camera-zoom-btn');
  if (zoomBtn) {
    const zoomLevels = ['1x', '2x', '0.5x'];
    let zoomIndex = 0;
    zoomBtn.addEventListener('click', function () {
      zoomIndex = (zoomIndex + 1) % zoomLevels.length;
      const label = zoomLevels[zoomIndex];
      zoomBtn.textContent = label;
      zoomBtn.setAttribute('aria-label', 'Zoom ' + label);
    });
  }

  // Flash AUTO yellow text rotation if clicked
  const flashValue = document.getElementById('flash-value');
  const flashTrigger = document.getElementById('flash-row');

  if (flashTrigger && flashValue) {
    const states = ['AUTO', 'ON', 'OFF'];
    let currentIndex = states.indexOf(flashValue.textContent.trim());
    if (currentIndex === -1) currentIndex = 0;

    flashTrigger.addEventListener('click', function() {
      currentIndex = (currentIndex + 1) % states.length;
      flashValue.textContent = states[currentIndex];
      
      // Update yellow text color for AUTO, grey for OFF, white for ON
      if (states[currentIndex] === 'AUTO') {
        flashValue.style.color = 'var(--nb-color-accent-yellow)';
      } else if (states[currentIndex] === 'OFF') {
        flashValue.style.color = 'var(--nb-color-gray)';
      } else {
        flashValue.style.color = 'var(--nb-color-white)';
      }
    });
  }
}
window.initToggles = initToggles;
