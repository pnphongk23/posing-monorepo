/* docs/prototype/scripts/onboarding.js */
/**
 * AI Pose Onboarding Engine
 * Handles multi-stage interactive onboarding, interest personalization,
 * live pose alignment simulation, permission priming, and local storage state.
 */

(function () {
  'use strict';

  // Available Interests / Vibes
  const INTEREST_OPTIONS = [
    { id: 'portrait', label: '📸 Portrait & Selfie', default: true },
    { id: 'cafe', label: '☕ Cafe & Aesthetic', default: true },
    { id: 'travel', label: '✈️ Travel & Landmarks', default: false },
    { id: 'street', label: '👟 Street & OOTD', default: false },
    { id: 'fitness', label: '🏋️ Fitness & Gym', default: false },
    { id: 'couples', label: '👥 Couples & Duo', default: false },
    { id: 'professional', label: '🏢 Headshots & Work', default: false }
  ];

  // State
  let currentStage = 1;
  const totalStages = 5;
  let selectedInterests = new Set(['portrait', 'cafe']);
  let isDemoAligned = false;
  let permissionsGranted = false;

  // DOM Elements
  const stageElements = document.querySelectorAll('.nb-onboarding__stage');
  const progressFill = document.getElementById('onboarding-progress-fill');
  const backBtn = document.getElementById('onboarding-back-btn');
  const skipBtn = document.getElementById('onboarding-skip-btn');
  const interestsGrid = document.getElementById('interests-grid');
  const selectedCounter = document.getElementById('selected-counter');
  const stage2Cta = document.getElementById('stage-2-cta');
  const alignmentSlider = document.getElementById('alignment-slider');
  const ghostOverlay = document.getElementById('ghost-overlay');
  const matchBanner = document.getElementById('match-banner');
  const sliderStatus = document.getElementById('slider-status');
  const enablePermBtn = document.getElementById('enable-permissions-btn');
  const deferPermBtn = document.getElementById('defer-permissions-btn');
  const curatedPillList = document.getElementById('curated-pill-list');
  const matchPercentBadge = document.getElementById('match-percent-badge');
  const matchPercentVal = document.getElementById('match-percent-val');
  const demoHudCorners = document.querySelectorAll('#demo-viewfinder .nb-hud-corner');

  // Initialize from Query Params or defaults
  function init() {
    const urlParams = new URLSearchParams(window.location.search);
    const stepParam = parseInt(urlParams.get('step'), 10);
    if (!isNaN(stepParam) && stepParam >= 1 && stepParam <= totalStages) {
      currentStage = stepParam;
    }

    renderInterests();
    bindEvents();
    updateUI();
  }

  // Render Interest Chips (Reddit / X Pattern)
  function renderInterests() {
    if (!interestsGrid) return;
    interestsGrid.innerHTML = '';

    INTEREST_OPTIONS.forEach((item) => {
      const chip = document.createElement('button');
      chip.type = 'button';
      chip.className = 'nb-interest-chip' + (selectedInterests.has(item.id) ? ' is-selected' : '');
      chip.setAttribute('role', 'checkbox');
      chip.setAttribute('aria-checked', selectedInterests.has(item.id) ? 'true' : 'false');
      chip.dataset.id = item.id;
      chip.innerHTML = `
        <span>${item.label}</span>
        <svg class="chip-check" viewBox="0 0 24 24" aria-hidden="true">
          <polyline points="20 6 9 17 4 12"></polyline>
        </svg>
      `;

      chip.addEventListener('click', () => toggleInterest(item.id, chip));
      interestsGrid.appendChild(chip);
    });

    updateInterestCounter();
  }

  function toggleInterest(id, chip) {
    if (selectedInterests.has(id)) {
      selectedInterests.delete(id);
      chip.classList.remove('is-selected');
      chip.setAttribute('aria-checked', 'false');
    } else {
      selectedInterests.add(id);
      chip.classList.add('is-selected');
      chip.setAttribute('aria-checked', 'true');
    }
    updateInterestCounter();
  }

  function updateInterestCounter() {
    if (!selectedCounter) return;
    const count = selectedInterests.size;
    selectedCounter.textContent = `${count} of ${INTEREST_OPTIONS.length} selected`;
    if (stage2Cta) {
      stage2Cta.disabled = count === 0;
      stage2Cta.textContent = count > 0 ? `Continue (${count})` : 'Select at least 1';
    }
  }

  // Interactive Pose Demo Simulator (Duolingo TTV Pattern)
  function handleSliderChange(val) {
    const offset = parseInt(val, 10);
    const absOffset = Math.abs(offset);
    // 0 is perfectly aligned, -35 to +35 is off
    const pxOffset = offset * 1.2;
    if (ghostOverlay) {
      ghostOverlay.style.transform = `translateX(${pxOffset}px)`;
    }

    // Dynamic match percentage (100% at center, ~23% at extremes)
    const matchPct = Math.max(20, Math.min(100, Math.round(100 - (absOffset * 2.2))));
    if (matchPercentVal) {
      matchPercentVal.textContent = `${matchPct}%`;
    }

    // Alignment threshold: within +/- 8 units
    if (absOffset <= 8) {
      if (!isDemoAligned) {
        isDemoAligned = true;
        if (ghostOverlay) ghostOverlay.classList.add('is-aligned');
        if (matchBanner) matchBanner.classList.add('is-visible');
        if (matchPercentBadge) matchPercentBadge.classList.add('is-perfect');
        demoHudCorners.forEach((corner) => corner.classList.add('is-aligned'));
        if (sliderStatus) {
          sliderStatus.textContent = 'Perfect match! ✨';
          sliderStatus.style.color = '#1B5E20';
        }
      }
    } else {
      if (isDemoAligned) {
        isDemoAligned = false;
        if (ghostOverlay) ghostOverlay.classList.remove('is-aligned');
        if (matchBanner) matchBanner.classList.remove('is-visible');
        if (matchPercentBadge) matchPercentBadge.classList.remove('is-perfect');
        demoHudCorners.forEach((corner) => corner.classList.remove('is-aligned'));
        if (sliderStatus) {
          sliderStatus.textContent = 'Drag to align joints';
          sliderStatus.style.color = 'var(--nb-color-gray)';
        }
      }
    }
  }

  // Update Progress and Stages Visibility
  function updateUI() {
    stageElements.forEach((el) => {
      const stageNum = parseInt(el.dataset.stage, 10);
      if (stageNum === currentStage) {
        el.classList.add('is-active');
        el.setAttribute('aria-hidden', 'false');
      } else {
        el.classList.remove('is-active');
        el.setAttribute('aria-hidden', 'true');
      }
    });

    const progressTrack = document.querySelector('.nb-onboarding__progress-track');
    if (progressFill && progressTrack) {
      const pct = (currentStage / totalStages) * 100;
      progressFill.style.width = `${pct}%`;
      progressTrack.setAttribute('aria-valuenow', Math.round(pct).toString());
    }

    if (backBtn) {
      backBtn.disabled = currentStage === 1;
    }

    const urlParams = new URLSearchParams(window.location.search);
    const isReplay = urlParams.get('replay') === 'true';

    if (skipBtn) {
      if (isReplay) {
        skipBtn.textContent = 'Exit';
        skipBtn.setAttribute('aria-label', 'Exit to Settings');
        skipBtn.style.display = 'inline-block';
      } else {
        skipBtn.style.display = currentStage >= 4 ? 'none' : 'inline-block';
      }
    }

    // If reached Stage 5, render summary pills (persistence happens on explicit CTA click)
    if (currentStage === 5 && curatedPillList) {
      curatedPillList.innerHTML = '';
      selectedInterests.forEach((id) => {
        const item = INTEREST_OPTIONS.find((opt) => opt.id === id);
        if (item) {
          const pill = document.createElement('span');
          pill.className = 'nb-curated-pill';
          pill.textContent = item.label;
          curatedPillList.appendChild(pill);
        }
      });
    }
  }

  function goToStage(stage) {
    if (stage >= 1 && stage <= totalStages) {
      currentStage = stage;
      updateUI();
    }
  }

  function nextStage() {
    goToStage(currentStage + 1);
  }

  function prevStage() {
    goToStage(currentStage - 1);
  }

  // Persist State to LocalStorage
  function persistOnboardingPreferences() {
    try {
      localStorage.setItem('has_completed_onboarding', 'true');
      localStorage.setItem(
        'user_selected_interests',
        JSON.stringify(Array.from(selectedInterests))
      );
      localStorage.setItem('onboarding_completed_at', new Date().toISOString());
      localStorage.setItem('camera_permissions_status', permissionsGranted ? 'granted' : 'deferred');
    } catch (e) {
      console.warn('LocalStorage unavailable in prototype environment', e);
    }
  }

  // Event Listeners
  function bindEvents() {
    if (backBtn) {
      backBtn.addEventListener('click', prevStage);
    }

    if (skipBtn) {
      skipBtn.addEventListener('click', () => {
        const isReplay = new URLSearchParams(window.location.search).get('replay') === 'true';
        if (isReplay) {
          window.location.href = 'settings.html';
          return;
        }
        persistOnboardingPreferences();
        window.location.href = 'poses-list.html?skipped_onboarding=true';
      });
    }

    // Stage 1 CTA
    const stage1Cta = document.getElementById('stage-1-cta');
    if (stage1Cta) stage1Cta.addEventListener('click', nextStage);

    // Stage 2 CTA
    if (stage2Cta) stage2Cta.addEventListener('click', nextStage);

    // Stage 3 CTA
    const stage3Cta = document.getElementById('stage-3-cta');
    if (stage3Cta) stage3Cta.addEventListener('click', nextStage);

    // Stage 3 Slider
    if (alignmentSlider) {
      alignmentSlider.addEventListener('input', (e) => {
        handleSliderChange(e.target.value);
      });
    }

    // Stage 4: Permissions Primer
    if (enablePermBtn) {
      enablePermBtn.addEventListener('click', () => {
        permissionsGranted = true;
        try {
          localStorage.setItem('camera_permissions_status', 'granted');
        } catch (e) {}
        enablePermBtn.textContent = 'Camera Access Enabled ✓';
        enablePermBtn.style.backgroundColor = 'var(--nb-color-accent-green)';
        setTimeout(() => {
          nextStage();
        }, 350);
      });
    }

    if (deferPermBtn) {
      deferPermBtn.addEventListener('click', () => {
        permissionsGranted = false;
        try {
          localStorage.setItem('camera_permissions_status', 'deferred');
        } catch (e) {}
        nextStage();
      });
    }

    // Stage 5 CTAs
    const launchCameraBtn = document.getElementById('launch-camera-btn');
    if (launchCameraBtn) {
      launchCameraBtn.addEventListener('click', () => {
        persistOnboardingPreferences();
        window.location.href = 'camera-live.html?from=onboarding';
      });
    }

    const browsePosesBtn = document.getElementById('browse-poses-btn');
    if (browsePosesBtn) {
      browsePosesBtn.addEventListener('click', () => {
        persistOnboardingPreferences();
        window.location.href = 'poses-list.html?from=onboarding';
      });
    }
  }

  // Initialize on DOM load
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
