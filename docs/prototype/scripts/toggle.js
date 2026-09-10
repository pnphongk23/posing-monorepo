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

    const zoomToggle = document.getElementById('camera-zoom-btn');
    const zoomSlider = document.getElementById('camera-zoom-slider');
    if (zoomToggle) {
      const zoomLevels = ['0.5x', '1x', '2x'];
      const zoomValue = document.getElementById('camera-zoom-value');

      if (zoomSlider && zoomSlider.type === 'range') {
        const zoomToggleValue = document.getElementById('camera-zoom-toggle-value');

        function updateZoomProgress() {
          const zoomIndex = Number(zoomSlider.value);
          const label = zoomLevels[zoomIndex] || zoomLevels[1];
          const progress = (zoomIndex / (zoomLevels.length - 1)) * 100;

          if (zoomValue) zoomValue.textContent = label;
          if (zoomToggleValue) zoomToggleValue.textContent = label;
          zoomSlider.style.setProperty('--zoom-progress', progress + '%');
          zoomSlider.setAttribute('aria-label', 'Zoom ' + label);
          zoomSlider.setAttribute('aria-valuetext', label);
          zoomToggle.setAttribute('aria-label', 'Scale factor, ' + label);
        }

        const zoomPanel = document.getElementById('camera-zoom-panel');
        const zoomControl = document.getElementById('camera-zoom-control');
        let zoomDismissTimer;
        let zoomCloseTimer;
        const reducedMotion = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
        const zoomTransitionMs = reducedMotion ? 0 : 180;

        function clearZoomDismissTimer() {
          window.clearTimeout(zoomDismissTimer);
        }

        function scheduleZoomDismiss() {
          clearZoomDismissTimer();
          if (!zoomPanel || zoomPanel.hidden) return;
          zoomDismissTimer = window.setTimeout(() => setZoomOpen(false), 2000);
        }

        function setZoomOpen(isOpen) {
          if (!zoomPanel || !zoomControl) return;
          window.clearTimeout(zoomCloseTimer);

          if (isOpen) {
            clearZoomDismissTimer();
            zoomPanel.hidden = false;
            zoomPanel.setAttribute('aria-hidden', 'false');
            zoomToggle.setAttribute('aria-expanded', 'true');
            zoomControl.classList.add('is-active');
            zoomPanel.classList.remove('is-open');
            void zoomPanel.offsetWidth;
            zoomPanel.classList.add('is-open');
            scheduleZoomDismiss();
            return;
          }

          clearZoomDismissTimer();
          zoomPanel.classList.remove('is-open');
          zoomPanel.setAttribute('aria-hidden', 'true');
          zoomToggle.setAttribute('aria-expanded', 'false');
          zoomControl.classList.remove('is-active');
          if (zoomPanel.contains(document.activeElement)) {
            zoomToggle.focus({ preventScroll: true });
          }
          zoomCloseTimer = window.setTimeout(() => {
            zoomPanel.hidden = true;
          }, zoomTransitionMs);
        }

        zoomToggle.addEventListener('click', function() {
          setZoomOpen(zoomPanel ? zoomPanel.hidden : false);
        });

        zoomSlider.addEventListener('input', function() {
          updateZoomProgress();
          scheduleZoomDismiss();
        });
        ['change', 'pointerdown', 'focusin', 'keydown'].forEach(eventName => {
          zoomSlider.addEventListener(eventName, scheduleZoomDismiss);
        });

        document.addEventListener('keydown', function(e) {
          if (e.key === 'Escape' && zoomPanel && !zoomPanel.hidden) {
            e.preventDefault();
            setZoomOpen(false);
          }
        });

        updateZoomProgress();
      } else {
        const legacyZoomLevels = ['1x', '2x', '0.5x'];
        let zoomIndex = 0;
        zoomToggle.addEventListener('click', function () {
          zoomIndex = (zoomIndex + 1) % legacyZoomLevels.length;
          const label = legacyZoomLevels[zoomIndex];
          const zoomLabel = zoomToggle.querySelector('span') || zoomToggle;
          zoomLabel.textContent = label;
          zoomToggle.setAttribute('aria-label', 'Zoom ' + label);
        });
      }
  }

  // Camera facing is a local prototype simulation. The button stays on the
  // capture surface and exposes the same intent as the native controller.
  const flipBtn = document.getElementById('camera-flip-btn');
  const cameraViewport = document.getElementById('camera-feed');
  if (flipBtn && cameraViewport) {
    let facing = 'back';
    cameraViewport.dataset.cameraFacing = facing;

    flipBtn.addEventListener('click', function() {
      facing = facing === 'back' ? 'front' : 'back';
      cameraViewport.dataset.cameraFacing = facing;
      const nextLabel = facing === 'back' ? 'Switch to front camera' : 'Switch to back camera';
      flipBtn.setAttribute('aria-label', nextLabel);

      const status = document.getElementById('camera-status');
      if (status) {
        status.textContent = facing === 'back' ? 'Back camera selected' : 'Front camera selected';
        status.hidden = false;
        status.dataset.tone = 'info';
        window.clearTimeout(status._hideTimer);
        status._hideTimer = window.setTimeout(() => {
          status.hidden = true;
        }, 1500);
      }
    });
  }

  // Flash setting rotation if clicked
  const flashValue = document.getElementById('flash-value');
  const flashTrigger = document.getElementById('flash-row');

  if (flashTrigger && flashValue) {
    const states = ['Auto', 'On', 'Off'];
    let currentIndex = states.indexOf(flashValue.textContent.trim());
    if (currentIndex === -1) currentIndex = 0;

    flashTrigger.addEventListener('click', function() {
      currentIndex = (currentIndex + 1) % states.length;
      flashValue.textContent = states[currentIndex];
      
      // Update yellow text color for Auto, grey for Off, white for On
      if (states[currentIndex] === 'Auto') {
        flashValue.style.color = 'var(--nb-color-accent-yellow)';
      } else if (states[currentIndex] === 'Off') {
        flashValue.style.color = 'var(--nb-color-gray)';
        } else {
          flashValue.style.color = 'var(--nb-color-white)';
        }
        flashTrigger.setAttribute('aria-label', 'Flash ' + states[currentIndex] + ', tap to change');
      });
  }
}
window.initToggles = initToggles;
