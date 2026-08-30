/* docs/prototype/scripts/paywall.js */
document.addEventListener('DOMContentLoaded', function () {
  const device = document.getElementById('paywall-device');
  const appSurface = document.getElementById('paywall-app-surface');
  const ctaBtn = document.getElementById('paywall-cta-btn');
  const ctaText = document.getElementById('paywall-cta-text');
  const ctaSpinner = document.getElementById('paywall-cta-spinner');
  const selectionSummary = document.getElementById('paywall-selection-summary');
  const options = Array.from(document.querySelectorAll('.paywall-option__input'));
  const stateButtons = Array.from(document.querySelectorAll('[data-state]'));
  const viewportButtons = Array.from(document.querySelectorAll('[data-viewport]'));
  const localeButtons = Array.from(document.querySelectorAll('[data-locale]'));

  const successModal = document.getElementById('paywall-success-modal');
  const errorModal = document.getElementById('paywall-error-modal');
  const unconfiguredModal = document.getElementById('paywall-unconfigured-modal');
  const termsModal = document.getElementById('paywall-terms-modal');
  const privacyModal = document.getElementById('paywall-privacy-modal');
  const modals = [successModal, errorModal, unconfiguredModal, termsModal, privacyModal].filter(Boolean);
  const successMessage = document.getElementById('success-modal-message');

  const closeBtn = document.getElementById('paywall-close-btn');
  const termsBtn = document.getElementById('paywall-terms-btn');
  const privacyBtn = document.getElementById('paywall-privacy-btn');
  const errorRetryBtn = document.getElementById('paywall-error-retry-btn');
  const sandboxDemoBtn = document.getElementById('paywall-unconfigured-sandbox-btn');
  const restoreBtn = document.getElementById('paywall-restore-btn');
  const planAnnouncement = document.getElementById('paywall-plan-announcement');

  const catalog = {
    usd: {
      annual: {
        priceHtml: '<strong>$39.99</strong><span> / year</span>',
        equiv: '$3.33 / month equivalent',
        terms: 'Billed today. Auto-renews yearly until you cancel.',
        cta: 'Continue with Annual',
        summary: '$39.99 billed today. Auto-renews yearly until you cancel.',
        announcement: 'Annual selected. 39 dollars and 99 cents billed today, auto-renewing yearly.'
      },
      monthly: {
        priceHtml: '<strong>$5.99</strong><span> / month</span>',
        terms: 'Billed today. Auto-renews monthly until you cancel.',
        cta: 'Continue with Monthly',
        summary: '$5.99 billed today. Auto-renews monthly until you cancel.',
        announcement: 'Monthly selected. 5 dollars and 99 cents billed today, auto-renewing monthly.'
      },
    },
    vnd: {
      annual: {
        priceHtml: '<strong>₫999,000</strong><span> / year</span>',
        equiv: '₫83,250 / month equivalent',
        terms: 'Billed today. Auto-renews yearly until you cancel.',
        cta: 'Continue with Annual',
        summary: '₫999,000 billed today. Auto-renews yearly until you cancel.',
        announcement: 'Annual selected. 999 thousand dong billed today, auto-renewing yearly. Planning anchor only.'
      },
      monthly: {
        priceHtml: '<strong>₫149,000</strong><span> / month</span>',
        terms: 'Billed today. Auto-renews monthly until you cancel.',
        cta: 'Continue with Monthly',
        summary: '₫149,000 billed today. Auto-renews monthly until you cancel.',
        announcement: 'Monthly selected. 149 thousand dong billed today, auto-renewing monthly. Planning anchor only.'
      },
    }
  };

  let simulationState = 'default';
  let activeLocale = 'usd';
  let activeModal = null;
  let modalTrigger = null;
  let purchaseTimer = null;
  let previousBodyOverflow = null;

  function hasPremium() {
    return sessionStorage.getItem('ai-pose.premium') === 'true';
  }

  function selectedPlan() {
    const selected = options.find(option => option.checked);
    return selected ? selected.value : 'annual';
  }

  function localeCatalog() {
    return catalog[activeLocale] || catalog.usd;
  }

  function planCopy(plan) {
    return localeCatalog()[plan] || localeCatalog().annual;
  }

  function setControlSelection(buttons, activeButton) {
    buttons.forEach(button => {
      const selected = button === activeButton;
      button.classList.toggle('is-active', selected);
      button.setAttribute('aria-pressed', String(selected));
    });
  }

  function setStateControl(state) {
    const activeButton = stateButtons.find(button => button.dataset.state === state);
    if (activeButton) setControlSelection(stateButtons, activeButton);
  }

  function setBusy(isBusy, label) {
    ctaBtn.disabled = isBusy;
    ctaBtn.setAttribute('aria-busy', String(isBusy));
    ctaSpinner.hidden = !isBusy;
    options.forEach(option => { option.disabled = isBusy; });
    if (label) ctaText.textContent = label;
  }

  function applyLocaleToCards() {
    const pack = localeCatalog();

    ['annual', 'monthly'].forEach(plan => {
      const node = document.querySelector(`[data-plan-price="${plan}"]`);
      const terms = document.querySelector(`[data-plan-terms="${plan}"]`);
      const equiv = document.querySelector(`[data-plan-equiv="${plan}"]`);
      if (node) node.innerHTML = pack[plan].priceHtml;
      if (terms) terms.textContent = pack[plan].terms;
      if (equiv && pack[plan].equiv) equiv.textContent = pack[plan].equiv;
    });
  }

  function updatePlanCopy(announce) {
    const details = planCopy(selectedPlan());
    if (!details) return;

    selectionSummary.textContent = details.summary;
    if (!ctaBtn.disabled) {
      ctaText.textContent = hasPremium() ? 'Premium unlocked' : details.cta;
    }
    if (announce && planAnnouncement) {
      planAnnouncement.textContent = details.announcement;
    }
  }

  function resolveSafeReturnTarget(rawTarget) {
    if (!rawTarget || !/^[a-z0-9-]+\.html(?:\?[^#]*)?$/.test(rawTarget)) return null;

    const candidate = new URL(rawTarget, window.location.href);
    const currentDirectory = window.location.pathname.slice(0, window.location.pathname.lastIndexOf('/') + 1);
    if (candidate.origin !== window.location.origin || !candidate.pathname.startsWith(currentDirectory)) return null;
    return candidate.href;
  }

  const requestedReturn = new URLSearchParams(window.location.search).get('return');
  const safeReturnTarget = resolveSafeReturnTarget(requestedReturn);

  function leavePaywall() {
    if (safeReturnTarget) {
      window.location.assign(safeReturnTarget);
      return;
    }

    if (document.referrer) {
      try {
        if (new URL(document.referrer).origin === window.location.origin) {
          window.history.back();
          return;
        }
      } catch (error) {
        // Ignore malformed referrers and use the local fallback.
      }
    }

    window.location.assign('poses-list.html');
  }

  function focusableElements(modal) {
    return Array.from(modal.querySelectorAll('button:not([disabled]), a[href], [tabindex]:not([tabindex="-1"])'));
  }

  function lockBodyScroll() {
    if (previousBodyOverflow !== null || !window.matchMedia('(max-width: 480px)').matches) return;
    previousBodyOverflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
  }

  function restoreBodyScroll() {
    if (previousBodyOverflow === null) return;
    document.body.style.overflow = previousBodyOverflow;
    previousBodyOverflow = null;
  }

  function openModal(modal, trigger) {
    if (!modal) return;
    if (activeModal && activeModal !== modal) closeModal(activeModal, false);

    lockBodyScroll();
    activeModal = modal;
    modalTrigger = trigger || document.activeElement;
    modal.inert = false;
    modal.classList.add('is-open');
    modal.setAttribute('aria-hidden', 'false');
    appSurface.inert = true;

    const firstAction = focusableElements(modal)[0];
    if (firstAction) window.setTimeout(() => firstAction.focus(), 0);
  }

  function closeModal(modal, restoreFocus) {
    if (!modal) return;
    modal.classList.remove('is-open');
    modal.setAttribute('aria-hidden', 'true');
    modal.inert = true;

    if (activeModal === modal) {
      activeModal = null;
      appSurface.inert = false;
      restoreBodyScroll();
      if (restoreFocus !== false && modalTrigger && typeof modalTrigger.focus === 'function') {
        modalTrigger.focus();
      }
      modalTrigger = null;
    }
  }

  function closeAllModals() {
    modals.forEach(modal => {
      modal.classList.remove('is-open');
      modal.setAttribute('aria-hidden', 'true');
      modal.inert = true;
    });
    activeModal = null;
    modalTrigger = null;
    appSurface.inert = false;
    restoreBodyScroll();
  }

  function showSuccess(message) {
    sessionStorage.setItem('ai-pose.premium', 'true');
    successMessage.textContent = message;
    setBusy(false);
    ctaText.textContent = 'Premium unlocked';
    openModal(successModal, ctaBtn);
    triggerConfetti();
  }

  function applyState(state) {
    if (purchaseTimer) {
      window.clearTimeout(purchaseTimer);
      purchaseTimer = null;
    }

    closeAllModals();
    simulationState = state;
    setBusy(false);
    applyLocaleToCards();

    switch (state) {
      case 'loading':
        setBusy(true, 'Processing simulated purchase…');
        break;
      case 'error':
        openModal(errorModal, document.activeElement);
        break;
      case 'success':
        showSuccess('Capture, Try Pose, and Gallery save or share are now available in this prototype session.');
        break;
      case 'restore':
        setBusy(true, 'Restoring simulated purchases…');
        purchaseTimer = window.setTimeout(() => {
          simulationState = 'default';
          setStateControl('success');
          showSuccess('Premium access was restored for this prototype session.');
        }, 1200);
        break;
      case 'unconfigured':
        break;
      default:
        simulationState = 'default';
        break;
    }

    updatePlanCopy(false);
  }

  function triggerPurchaseFlow() {
    if (simulationState === 'unconfigured') {
      openModal(unconfiguredModal, ctaBtn);
      return;
    }

    if (hasPremium()) {
      openModal(successModal, ctaBtn);
      return;
    }

    setBusy(true, 'Connecting to simulated App Store…');
    purchaseTimer = window.setTimeout(() => {
      purchaseTimer = null;
      if (simulationState === 'error') {
        setBusy(false);
        updatePlanCopy(false);
        openModal(errorModal, ctaBtn);
        return;
      }

      showSuccess('Capture, Try Pose, and Gallery save or share are now available in this prototype session.');
    }, 1200);
  }

  modals.forEach(modal => { modal.inert = true; });

  document.addEventListener('keydown', event => {
    if (!activeModal) return;

    if (event.key === 'Escape' || event.key === 'Esc') {
      event.preventDefault();
      const closingModal = activeModal;
      closeModal(closingModal, closingModal !== successModal);
      if (closingModal === successModal) leavePaywall();
      return;
    }

    if (event.key === 'Tab') {
      const focusables = focusableElements(activeModal);
      if (!focusables.length) return;
      const first = focusables[0];
      const last = focusables[focusables.length - 1];
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    }
  });

  closeBtn.addEventListener('click', leavePaywall);
  ctaBtn.addEventListener('click', triggerPurchaseFlow);
  options.forEach(option => option.addEventListener('change', () => updatePlanCopy(true)));

  termsBtn.addEventListener('click', event => openModal(termsModal, event.currentTarget));
  privacyBtn.addEventListener('click', event => openModal(privacyModal, event.currentTarget));

  errorRetryBtn.addEventListener('click', () => {
    closeModal(errorModal, false);
    simulationState = 'default';
    setStateControl('default');
    triggerPurchaseFlow();
  });

  sandboxDemoBtn.addEventListener('click', () => {
    closeModal(unconfiguredModal, false);
    applyState('default');
    setStateControl('default');
    ctaBtn.focus();
  });

  restoreBtn.addEventListener('click', event => {
    event.preventDefault();
    if (simulationState === 'unconfigured') {
      openModal(unconfiguredModal, event.currentTarget);
      return;
    }
    applyState('restore');
  });

  stateButtons.forEach(button => {
    button.addEventListener('click', () => {
      setControlSelection(stateButtons, button);
      applyState(button.dataset.state);
    });
  });

  viewportButtons.forEach(button => {
    button.addEventListener('click', () => {
      setControlSelection(viewportButtons, button);
      device.className = `paywall-device paywall-device--${button.dataset.viewport}`;
    });
  });

  localeButtons.forEach(button => {
    button.addEventListener('click', () => {
      setControlSelection(localeButtons, button);
      activeLocale = button.dataset.locale === 'vnd' ? 'vnd' : 'usd';
      applyLocaleToCards();
      updatePlanCopy(true);
    });
  });

  document.querySelectorAll('[data-close-modal]').forEach(button => {
    button.addEventListener('click', event => {
      const modal = event.currentTarget.closest('.nb-modal-overlay');
      closeModal(modal, modal !== successModal);
      if (modal === successModal) leavePaywall();
    });
  });

  // Keep prototype variants addressable without placing debug controls on the
  // purchase surface. This preserves deterministic review URLs such as
  // ?locale=vnd, ?viewport=tablet, and ?state=error.
  const previewParams = new URLSearchParams(window.location.search);
  const previewLocale = previewParams.get('locale');
  const previewViewport = previewParams.get('viewport');
  const previewState = previewParams.get('state');
  const previewViewports = ['mobile', 'tablet', 'desktop'];
  const previewStates = ['default', 'loading', 'success', 'error', 'restore', 'unconfigured'];

  if (previewLocale === 'vnd') activeLocale = 'vnd';
  if (previewViewports.includes(previewViewport)) {
    device.className = `paywall-device paywall-device--${previewViewport}`;
  }

  function triggerConfetti() {
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;

    const canvas = document.createElement('canvas');
    const context = canvas.getContext('2d');
    if (!context) return;

    canvas.className = 'paywall-confetti';
    canvas.style.cssText = 'position:fixed;inset:0;width:100vw;height:100vh;pointer-events:none;z-index:300';
    document.body.appendChild(canvas);

    let width;
    let height;
    let animationId;
    const colors = ['#E89CAE', '#7FBBE6', '#FED766', '#B5E2B9'];
    const pieces = Array.from({ length: 60 }, (_, index) => ({
      color: colors[index % colors.length],
      radius: 4 + Math.random() * 4,
      tilt: Math.random() * Math.PI,
      velocity: 2 + Math.random() * 3,
      x: Math.random(),
      y: -Math.random()
    }));

    function resizeCanvas() {
      width = canvas.width = window.innerWidth;
      height = canvas.height = window.innerHeight;
    }

    function cleanup() {
      window.cancelAnimationFrame(animationId);
      window.removeEventListener('resize', resizeCanvas);
      canvas.remove();
    }

    function draw() {
      context.clearRect(0, 0, width, height);
      let visible = 0;
      pieces.forEach(piece => {
        piece.y += piece.velocity / height;
        piece.tilt += 0.08;
        if (piece.y < 1.1) visible += 1;
        context.strokeStyle = piece.color;
        context.lineWidth = piece.radius;
        context.beginPath();
        context.moveTo(piece.x * width, piece.y * height);
        context.lineTo(piece.x * width + Math.sin(piece.tilt) * 10, piece.y * height + 8);
        context.stroke();
      });
      if (visible) animationId = window.requestAnimationFrame(draw);
      else cleanup();
    }

    resizeCanvas();
    window.addEventListener('resize', resizeCanvas);
    draw();
    window.setTimeout(cleanup, 4000);
  }

  setControlSelection(stateButtons, stateButtons.find(button => button.dataset.state === 'default'));
  setControlSelection(viewportButtons, viewportButtons.find(button => button.dataset.viewport === 'mobile'));
  setControlSelection(localeButtons, localeButtons.find(button => button.dataset.locale === 'usd'));
  applyLocaleToCards();
  updatePlanCopy(false);
  if (previewStates.includes(previewState)) applyState(previewState);
});
