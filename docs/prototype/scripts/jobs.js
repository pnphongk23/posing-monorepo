/* docs/prototype/scripts/jobs.js
 * Single shared job store + Jobs page controller for server-authoritative jobs.
 * Exposes window.PoseJobsDemo interface and handles the Jobs screen DOM when present.
 */
(function (window, document) {
  'use strict';

  const STORAGE_KEY = 'snap-pose.prototype.jobs.v2';
  let memoryJobs = [];
  let isSimulatedOffline = false;

  function uid(prefix) {
    return prefix + '-' + (crypto.randomUUID ? crypto.randomUUID().slice(0, 8) : Date.now().toString(36) + '-' + Math.random().toString(36).slice(2, 6));
  }

  function readStorage() {
    try {
      const raw = localStorage.getItem(STORAGE_KEY);
      if (!raw) return memoryJobs;
      const parsed = JSON.parse(raw);
      return Array.isArray(parsed) ? parsed : [];
    } catch (_) {
      return memoryJobs;
    }
  }

  function writeStorage(jobs) {
    memoryJobs = jobs;
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(jobs));
    } catch (_) {
      /* Fallback to in-memory */
    }
    window.dispatchEvent(new CustomEvent('pose-jobs-change', { detail: { jobs } }));
  }

  function advanceSimulation(job, now) {
    if (job.frozen) return; // Preserved static fixture state
    const elapsed = now - job.attemptAt;

    if (job.status === 'queued' && elapsed >= 1800) {
      job.status = 'processing';
    }
    if (job.status === 'processing' && elapsed >= 4300) {
      if (job.scenario === 'extract-failed' && job.attempt === 1) {
        job.status = 'failed';
        job.error = 'Pose extraction could not finish.';
      } else {
        job.status = 'ready';
        job.error = '';
        job.poseId = job.poseId || uid('pose');
      }
    }
  }

  function all() {
    const jobs = readStorage();
    const before = JSON.stringify(jobs);
    const now = Date.now();
    jobs.forEach(job => advanceSimulation(job, now));
    if (JSON.stringify(jobs) !== before) {
      writeStorage(jobs);
    }
    return jobs.slice().sort((a, b) => b.createdAt - a.createdAt);
  }

  function get(id) {
    return all().find(job => job.id === id || job.poseId === id || job.localId === id) || null;
  }

  function countActive() {
    // Active jobs: queued and processing only
    const activeStatuses = ['queued', 'processing'];
    return all().filter(job => activeStatuses.includes(job.status)).length;
  }

  function create(data, scenario) {
    const now = Date.now();
    const id = uid('job');
    const job = {
      id,
      localId: id, // compatibility alias
      poseId: null,
      name: (data && data.name) ? String(data.name).trim() : 'Untitled pose',
      tags: (data && Array.isArray(data.tags)) ? data.tags : (data && data.tags ? [data.tags] : ['Portrait']),
      description: (data && data.description) ? String(data.description).trim() : '',
      photoName: (data && data.photoName) ? String(data.photoName).trim() : 'Sample photo',
      photoUrl: (data && data.photoUrl) ? data.photoUrl : '',
      createdAt: now,
      attemptAt: now,
      attempt: 1,
      status: 'queued',
      scenario: scenario || '',
      frozen: false,
      error: ''
    };
    const jobs = readStorage();
    jobs.unshift(job);
    writeStorage(jobs);
    return job;
  }

  function update(id, action) {
    const jobs = all();
    const job = jobs.find(item => item.id === id || item.localId === id);
    if (!job) return false;

    if (action === 'retry' && job.status === 'failed') {
      job.attempt += 1;
      job.attemptAt = Date.now();
      job.status = 'queued';
      job.error = '';
      job.frozen = false;
    } else if (action === 'hide' || action === 'remove') {
      const filtered = jobs.filter(item => item.id !== id && item.localId !== id);
      writeStorage(filtered);
      return true;
    } else {
      return false;
    }
    writeStorage(jobs);
    return true;
  }

  function remove(id) {
    return update(id, 'hide');
  }

  function clearAll() {
    writeStorage([]);
  }

  function setOffline(offlineState) {
    isSimulatedOffline = Boolean(offlineState);
    window.dispatchEvent(new Event('pose-jobs-offline-change'));
  }

  function isOffline() {
    return isSimulatedOffline;
  }

  function seedFixtures(preset = 'all') {
    const now = Date.now();
    let fixtures = [];

    if (preset === 'offline') {
      setOffline(true);
    } else if (isSimulatedOffline) {
      setOffline(false);
    }

    switch (preset) {
      case 'empty':
        fixtures = [];
        break;

      case 'in-progress':
      case 'processing':
        fixtures = [
          { name: 'Street fashion', status: 'queued', age: 800, attempt: 1 },
          { name: 'Studio portrait', status: 'processing', age: 2500, attempt: 1 }
        ];
        break;

      case 'queued':
        fixtures = [
          { name: 'Street fashion', status: 'queued', age: 800, attempt: 1 }
        ];
        break;

      case 'finished':
      case 'finish':
        fixtures = [
          { name: 'Cafe seating', status: 'ready', age: 8000, attempt: 1, poseId: uid('pose') },
          { name: 'Low-light dance', status: 'failed', age: 8000, attempt: 1, error: 'Pose extraction could not finish.' }
        ];
        break;

      case 'failed':
      case 'error':
        fixtures = [
          { name: 'Low-light dance', status: 'failed', age: 8000, attempt: 1, error: 'Pose extraction could not finish.' }
        ];
        break;

      case 'ready':
        fixtures = [
          { name: 'Cafe seating', status: 'ready', age: 8000, attempt: 1, poseId: uid('pose') }
        ];
        break;

      case 'offline':
        fixtures = [
          { name: 'Street fashion', status: 'queued', age: 800, attempt: 1 },
          { name: 'Studio portrait', status: 'processing', age: 2500, attempt: 1 },
          { name: 'Cafe seating', status: 'ready', age: 8000, attempt: 1, poseId: uid('pose') },
          { name: 'Low-light dance', status: 'failed', age: 8000, attempt: 1, error: 'Pose extraction could not finish.' }
        ];
        break;

      case 'all':
      default:
        fixtures = [
          { name: 'Street fashion', status: 'queued', age: 800, attempt: 1 },
          { name: 'Studio portrait', status: 'processing', age: 2500, attempt: 1 },
          { name: 'Cafe seating', status: 'ready', age: 8000, attempt: 1, poseId: uid('pose') },
          { name: 'Low-light dance', status: 'failed', age: 8000, attempt: 1, error: 'Pose extraction could not finish.' }
        ];
        break;
    }

    const fixtureDescriptions = {
      'Street fashion': 'Walking with a relaxed posture',
      'Studio portrait': 'Balanced standing pose',
      'Cafe seating': 'Relaxed seated posture',
      'Low-light dance': 'Dynamic dance pose'
    };

    const items = fixtures.map((f, index) => {
      const id = uid('job');
      return {
        id,
        localId: id,
        poseId: f.poseId || (f.status === 'ready' ? uid('pose') : null),
        name: f.name,
        tags: ['Portrait', 'Sample'],
        description: f.description || fixtureDescriptions[f.name] || '',
        photoName: 'Photo library sample',
        photoUrl: '',
        createdAt: now - index * 1000,
        attemptAt: now - (f.age || 0),
        attempt: f.attempt || 1,
        status: f.status,
        scenario: '',
        frozen: true, // Freeze seeded fixtures so test views remain deterministic
        error: f.error || ''
      };
    });

    writeStorage(items);
  }

  // Public Interface on window.PoseJobsDemo
  window.PoseJobsDemo = {
    all,
    get,
    create,
    update,
    remove,
    hide: remove,
    clearAll,
    countActive,
    setOffline,
    isOffline,
    seedFixtures
  };

  /* ──────────────────────────────────────────────────────────────────────────
   * JOBS PAGE DOM CONTROLLER
   * Guarded so non-Jobs screens (like Add Pose or Poses list) run without errors.
   * ────────────────────────────────────────────────────────────────────────── */
  function initJobsScreen() {
    const screenRoot = document.getElementById('jobs-screen');
    const processingList = document.getElementById('jobs-processing-list');
    const finishList = document.getElementById('jobs-finish-list');

    if (!screenRoot && !processingList) return; // Guard: not on Jobs screen

    const params = new URLSearchParams(window.location.search);
    const fixtureParam = params.get('fixture');
    const stateParam = params.get('state');
    const finishPresets = new Set(['finished', 'finish', 'error', 'failed', 'ready']);
    const requestedTab = params.get('tab');
    let activeTab = ['processing', 'finish'].includes(requestedTab)
      ? requestedTab
      : (finishPresets.has(fixtureParam || stateParam) ? 'finish' : 'processing');

    // Handle initial state fixture seeding
    if (stateParam === 'offline' || fixtureParam === 'offline') {
      setOffline(true);
    } else {
      setOffline(false);
    }

    if (fixtureParam) {
      seedFixtures(fixtureParam);
    } else if (stateParam) {
      seedFixtures(stateParam);
    } else if (readStorage().length === 0) {
      seedFixtures('all');
    }

    const backBtn = document.getElementById('jobs-back');
    if (backBtn && params.get('from') === 'add-pose') {
      backBtn.href = 'add-pose.html';
      backBtn.setAttribute('aria-label', 'Back to Add pose');
    }

    const tabsEl = document.getElementById('jobs-tabs');
    const processingTab = document.getElementById('jobs-tab-processing');
    const finishTab = document.getElementById('jobs-tab-finish');
    const processingSection = document.getElementById('jobs-panel-processing');
    const finishSection = document.getElementById('jobs-panel-finish');
    const processingEmpty = document.getElementById('jobs-processing-empty');
    const finishEmpty = document.getElementById('jobs-finish-empty');
    const finishFilterEl = document.getElementById('jobs-finish-filter');
    const emptyState = document.getElementById('jobs-empty');
    const offlineBanner = document.getElementById('jobs-offline-banner');

    // Hide Confirmation Sheet elements
    const removeModal = document.getElementById('jobs-remove-modal');
    const removeModalTitle = document.getElementById('jobs-remove-title');
    const removeModalCopy = document.getElementById('jobs-remove-copy');
    const removeModalCancel = document.getElementById('jobs-remove-cancel');
    const removeModalConfirm = document.getElementById('jobs-remove-confirm');
    let pendingRemoveJobId = null;
    let activeSwipedJobId = null;

    // Fixture Switcher
    const switcherSelect = document.getElementById('jobs-fixture-select');
    if (switcherSelect) {
      const activePreset = fixtureParam || stateParam || (isOffline() ? 'offline' : 'all');
      switcherSelect.value = activePreset;
      switcherSelect.addEventListener('change', (e) => {
        const val = e.target.value;
        if (val === 'offline') {
          setOffline(true);
        } else {
          setOffline(false);
        }
        seedFixtures(val);
        activeTab = finishPresets.has(val) ? 'finish' : 'processing';
        if (finishFilterEl) finishFilterEl.value = 'all';
        const nextUrl = new URL(window.location.href);
        nextUrl.searchParams.set('fixture', val);
        window.history.replaceState({}, '', nextUrl.toString());
        lastDataSignature = '';
        render();
      });
    }

    const STATUS_CONFIG = {
      queued: { label: 'Queued', tab: 'processing', badgeClass: 'jobs-badge--yellow' },
      processing: { label: 'Processing', tab: 'processing', badgeClass: 'jobs-badge--yellow' },
      failed: { label: 'Failed', tab: 'finish', result: 'fail', canHide: true, badgeClass: 'jobs-badge--pink', isError: true, errorCopy: 'Pose extraction could not finish.' },
      ready: { label: 'Ready', tab: 'finish', result: 'success', canHide: true, badgeClass: 'jobs-badge--green' }
    };

    function el(tag, className, textContent) {
      const node = document.createElement(tag);
      if (className) node.className = className;
      if (textContent !== undefined && textContent !== null) node.textContent = textContent;
      return node;
    }

    function renderThumbnail(job) {
      const thumb = el('div', 'jobs-card__thumb');
      thumb.setAttribute('aria-hidden', 'true');
      thumb.innerHTML = `
        <svg viewBox="0 0 24 24" class="jobs-card__stick-icon" aria-hidden="true" focusable="false">
          <circle cx="12" cy="6" r="2.5" fill="currentColor"/>
          <line x1="12" y1="8.5" x2="12" y2="15" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>
          <line x1="12" y1="10.5" x2="8" y2="13.5" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>
          <line x1="12" y1="10.5" x2="16" y2="13.5" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>
          <line x1="12" y1="15" x2="9" y2="20" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>
          <line x1="12" y1="15" x2="15" y2="20" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>
        </svg>
      `;
      return thumb;
    }

    function attachSwipeBehavior(rowWrap, card, job) {
      let startX = 0;
      let currentX = 0;
      let isDragging = false;
      const threshold = 40;
      const revealWidth = 84;

      function updateRevealAccessibility(isOpen) {
        const revealBtn = rowWrap.querySelector('.jobs-row__delete-reveal');
        if (revealBtn) {
          if (isOpen) {
            revealBtn.removeAttribute('aria-hidden');
            revealBtn.tabIndex = 0;
          } else {
            revealBtn.setAttribute('aria-hidden', 'true');
            revealBtn.tabIndex = -1;
          }
        }
      }

      function resetPosition() {
        card.style.transform = 'translateX(0px)';
        card.classList.remove('is-swiping');
        updateRevealAccessibility(false);
        if (activeSwipedJobId === (job.id || job.localId)) {
          activeSwipedJobId = null;
        }
      }

      function openSwipe() {
        const currentJobId = job.id || job.localId;
        if (activeSwipedJobId && activeSwipedJobId !== currentJobId) {
          const otherCard = document.getElementById('job-' + activeSwipedJobId);
          if (otherCard && typeof otherCard._resetSwipe === 'function') {
            otherCard._resetSwipe();
          }
        }
        card.style.transform = `translateX(-${revealWidth}px)`;
        card.classList.remove('is-swiping');
        updateRevealAccessibility(true);
        activeSwipedJobId = currentJobId;
      }

      function onStart(e) {
        if (e.target.closest('button') || e.target.closest('a')) return;
        const pageX = e.touches ? e.touches[0].pageX : e.pageX;
        startX = pageX;
        currentX = pageX;
        isDragging = true;
        card.classList.add('is-swiping');

        window.addEventListener('mousemove', onMove);
        window.addEventListener('mouseup', onEnd);
        window.addEventListener('touchmove', onMove, { passive: true });
        window.addEventListener('touchend', onEnd);
      }

      function onMove(e) {
        if (!isDragging) return;
        const pageX = e.touches ? e.touches[0].pageX : e.pageX;
        currentX = pageX;
        const diff = currentX - startX;
        if (diff < 0) {
          const clamped = Math.max(diff, -revealWidth - 20);
          card.style.transform = `translateX(${clamped}px)`;
        } else {
          card.style.transform = 'translateX(0px)';
        }
      }

      function onEnd() {
        if (!isDragging) return;
        isDragging = false;
        card.classList.remove('is-swiping');

        window.removeEventListener('mousemove', onMove);
        window.removeEventListener('mouseup', onEnd);
        window.removeEventListener('touchmove', onMove);
        window.removeEventListener('touchend', onEnd);

        const diff = currentX - startX;
        if (diff < -threshold) {
          openSwipe();
        } else {
          resetPosition();
        }
      }

      card.addEventListener('touchstart', onStart, { passive: true });
      card.addEventListener('mousedown', onStart);

      const revealBtn = rowWrap.querySelector('.jobs-row__delete-reveal');
      if (revealBtn) {
        revealBtn.addEventListener('click', (e) => {
          e.stopPropagation();
          openRemoveModal(job, revealBtn);
        });
      }

      card._resetSwipe = resetPosition;
    }

    function renderJobCard(job, currentlyOffline) {
      const cfg = STATUS_CONFIG[job.status] || { label: 'Failed', tab: 'finish', result: 'fail', canHide: true, badgeClass: 'jobs-badge--pink', isError: true, errorCopy: 'Pose extraction could not finish.' };
      const canHide = cfg.canHide === true;
      const jobId = job.id || job.localId;

      const rowWrap = el('li', 'jobs-row');
      rowWrap.id = 'job-row-' + jobId;

      if (canHide) {
        rowWrap.classList.add('jobs-row--swipeable');
        const reveal = el('button', 'jobs-row__delete-reveal', '');
        reveal.type = 'button';
        reveal.setAttribute('aria-label', `Hide ${job.name}`);
        reveal.setAttribute('aria-hidden', 'true');
        reveal.tabIndex = -1;
        reveal.innerHTML = `
          <svg aria-hidden="true" style="width:20px;height:20px;stroke:currentColor;fill:none;stroke-width:2.5;"><use href="#icon-trash"></use></svg>
          <span>Hide</span>
        `;
        rowWrap.appendChild(reveal);
      }

      const card = el('div', 'jobs-card nb-card');
      card.dataset.state = job.status;
      card.id = 'job-' + jobId;

      // Top layout: Thumb + Info + Badge
      const mainRow = el('div', 'jobs-card__main');
      mainRow.appendChild(renderThumbnail(job));

      const info = el('div', 'jobs-card__info');
      const headerLine = el('div', 'jobs-card__header-line');
      const title = el('h3', 'jobs-card__title', job.name);
      const badge = el('span', `jobs-badge ${cfg.badgeClass}`, cfg.label);
      headerLine.append(title, badge);

      const detailParts = [];
      const description = String(job.description || '').trim();
      if (description) detailParts.push(`Description: ${description}`);
      if (job.attempt > 1) detailParts.push(`Attempt ${job.attempt}`);
      info.appendChild(headerLine);
      if (detailParts.length > 0) {
        info.appendChild(el('p', 'jobs-card__detail', detailParts.join(' · ')));
      }

      if (cfg.isError) {
        const errorCopy = el('p', 'jobs-card__desc jobs-card__desc--error', job.error || cfg.errorCopy);
        info.appendChild(errorCopy);
      }

      mainRow.appendChild(info);
      card.appendChild(mainRow);

      // Trailing Action Row: Retry for failed, View pose for ready
      const actionRow = el('div', 'jobs-card__actions');

      if (job.status === 'failed') {
        const retryBtn = el('button', 'nb-btn nb-btn--yellow jobs-card__btn', 'Retry');
        retryBtn.type = 'button';
        retryBtn.disabled = currentlyOffline;
        if (currentlyOffline) retryBtn.setAttribute('aria-disabled', 'true');
        retryBtn.addEventListener('click', () => {
          if (currentlyOffline) return;
          update(jobId, 'retry');
          activateTab('processing');
        });
        actionRow.appendChild(retryBtn);
      } else if (job.status === 'ready') {
        const viewLink = el('a', 'nb-btn nb-btn--green jobs-card__btn', 'View pose');
        viewLink.href = 'poses-list.html?demoPose=' + encodeURIComponent(job.poseId || jobId);
        actionRow.appendChild(viewLink);
      }

      if (actionRow.childNodes.length > 0) {
        card.appendChild(actionRow);
      }

      rowWrap.appendChild(card);

      if (canHide) {
        attachSwipeBehavior(rowWrap, card, job);
      }

      return rowWrap;
    }

    let lastFocusedTrigger = null;

    function openRemoveModal(job, triggerEl) {
      const jobId = job.id || job.localId;
      pendingRemoveJobId = jobId;
      lastFocusedTrigger = triggerEl || (document.getElementById('job-row-' + jobId) ? document.getElementById('job-row-' + jobId).querySelector('.jobs-row__delete-reveal') : null) || document.activeElement;

      if (removeModalTitle) {
        removeModalTitle.textContent = 'Hide job?';
      }
      if (removeModalCopy) {
        if (job.status === 'ready') {
          removeModalCopy.textContent = 'This hides the job from your list. The saved pose in your library is not deleted.';
        } else {
          removeModalCopy.textContent = 'This hides the job from your list.';
        }
      }
      if (removeModal) {
        removeModal.hidden = false;
        removeModal.classList.add('is-visible');
        removeModal.setAttribute('aria-hidden', 'false');
        if (removeModalConfirm) removeModalConfirm.focus();
      }
    }

    function closeRemoveModal(options) {
      const opts = options || {};
      const restoreTrigger = opts.restoreTrigger !== false;
      const targetJobId = pendingRemoveJobId;
      pendingRemoveJobId = null;

      if (restoreTrigger) {
        let returnTarget = null;
        if (lastFocusedTrigger && document.body.contains(lastFocusedTrigger)) {
          returnTarget = lastFocusedTrigger;
        } else if (targetJobId) {
          const row = document.getElementById('job-row-' + targetJobId);
          if (row) returnTarget = row.querySelector('.jobs-row__delete-reveal');
        }

        if (returnTarget) {
          returnTarget.removeAttribute('aria-hidden');
          returnTarget.tabIndex = 0;
          returnTarget.focus();
        } else {
          const backBtn = document.getElementById('jobs-back');
          if (backBtn) backBtn.focus();
        }
      } else {
        const backBtn = document.getElementById('jobs-back');
        if (backBtn) backBtn.focus();
      }

      if (removeModal) {
        removeModal.hidden = true;
        removeModal.classList.remove('is-visible');
        removeModal.setAttribute('aria-hidden', 'true');
      }
    }

    if (removeModalCancel) {
      removeModalCancel.addEventListener('click', () => {
        closeRemoveModal({ restoreTrigger: true });
      });
    }
    if (removeModalConfirm) {
      removeModalConfirm.addEventListener('click', () => {
        if (pendingRemoveJobId) {
          const idToRemove = pendingRemoveJobId;
          closeRemoveModal({ restoreTrigger: false });
          if (activeSwipedJobId === idToRemove) {
            activeSwipedJobId = null;
          }
          remove(idToRemove);
          lastDataSignature = '';
          render();
        }
      });
    }

    if (removeModal) {
      removeModal.addEventListener('click', (e) => {
        if (e.target === removeModal) {
          closeRemoveModal({ restoreTrigger: true });
        }
      });
    }

    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && removeModal && !removeModal.hidden) {
        closeRemoveModal({ restoreTrigger: true });
      }
    });

    let lastDataSignature = '';
    let hasAppliedHighlightTab = false;

    function updateTabState(hasJobs) {
      const onProcessing = activeTab === 'processing';

      if (tabsEl) tabsEl.hidden = !hasJobs;
      if (processingTab) {
        processingTab.setAttribute('aria-selected', String(onProcessing));
        processingTab.tabIndex = onProcessing ? 0 : -1;
      }
      if (finishTab) {
        finishTab.setAttribute('aria-selected', String(!onProcessing));
        finishTab.tabIndex = onProcessing ? -1 : 0;
      }
      if (processingSection) processingSection.hidden = !hasJobs || !onProcessing;
      if (finishSection) finishSection.hidden = !hasJobs || onProcessing;
    }

    function activateTab(tab, moveFocus = false) {
      activeTab = tab;
      activeSwipedJobId = null;
      lastDataSignature = '';
      render();
      if (moveFocus) {
        const target = tab === 'finish' ? finishTab : processingTab;
        if (target) target.focus();
      }
    }

    if (processingTab) {
      processingTab.addEventListener('click', () => activateTab('processing'));
    }
    if (finishTab) {
      finishTab.addEventListener('click', () => activateTab('finish'));
    }
    if (tabsEl) {
      tabsEl.addEventListener('keydown', (event) => {
        if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) return;
        event.preventDefault();
        if (event.key === 'Home') return activateTab('processing', true);
        if (event.key === 'End') return activateTab('finish', true);
        const nextTab = event.key === 'ArrowRight'
          ? (activeTab === 'processing' ? 'finish' : 'processing')
          : (activeTab === 'finish' ? 'processing' : 'finish');
        activateTab(nextTab, true);
      });
    }
    if (finishFilterEl) {
      finishFilterEl.addEventListener('change', () => {
        activeSwipedJobId = null;
        lastDataSignature = '';
        render();
      });
    }

    function render() {
      const offline = isOffline();
      const rawJobs = all();
      // When offline, no jobs are available/shown
      const jobs = offline ? [] : rawJobs;
      const resultFilter = finishFilterEl ? finishFilterEl.value : 'all';
      const highlightId = params.get('job');
      const highlightedJob = highlightId ? jobs.find(job => (job.id === highlightId || job.localId === highlightId)) : null;
      if (highlightedJob && !requestedTab && !hasAppliedHighlightTab) {
        activeTab = (STATUS_CONFIG[highlightedJob.status] || {}).tab || activeTab;
      }
      hasAppliedHighlightTab = true;
      const currentSignature = JSON.stringify(jobs) + '|' + offline + '|' + activeTab + '|' + resultFilter;

      if (offlineBanner) {
        offlineBanner.hidden = !offline;
      }

      const total = jobs.length;
      updateTabState(total > 0);

      if (total === 0) {
        if (emptyState) {
          emptyState.hidden = offline; // Hide generic empty state when offline (banner communicates state)
        }
        if (processingSection) processingSection.hidden = true;
        if (finishSection) finishSection.hidden = true;
        if (processingList) processingList.replaceChildren();
        if (finishList) finishList.replaceChildren();
        lastDataSignature = currentSignature;
        return;
      }

      if (emptyState) emptyState.hidden = true;

      // Only recreate DOM if data signature changed
      if (currentSignature !== lastDataSignature) {
        lastDataSignature = currentSignature;

        const processingJobs = jobs.filter(job => (STATUS_CONFIG[job.status] || {}).tab === 'processing');
        const finishJobs = jobs.filter(job => {
          const cfg = STATUS_CONFIG[job.status] || { tab: 'finish', result: 'fail' };
          return cfg.tab === 'finish' && (resultFilter === 'all' || cfg.result === resultFilter);
        });

        if (processingList) {
          processingList.replaceChildren(...processingJobs.map(job => renderJobCard(job, offline)));
        }
        if (processingEmpty) {
          processingEmpty.textContent = processingJobs.length === 0 ? 'No jobs are processing.' : '';
          processingEmpty.hidden = processingJobs.length > 0;
        }

        if (finishList) {
          finishList.replaceChildren(...finishJobs.map(job => renderJobCard(job, offline)));
        }
        if (finishEmpty) {
          const emptyMessage = resultFilter === 'success'
            ? 'No successful poses yet.'
            : resultFilter === 'fail'
              ? 'No failed requests.'
              : 'No finished requests yet.';
          finishEmpty.textContent = finishJobs.length === 0 ? emptyMessage : '';
          finishEmpty.hidden = finishJobs.length > 0;
        }

        // Preserve swiped card state across data re-renders
        if (activeSwipedJobId) {
          const swipedCard = document.getElementById('job-' + activeSwipedJobId);
          if (swipedCard) {
            swipedCard.style.transform = 'translateX(-84px)';
            const swipedRow = swipedCard.closest('.jobs-row');
            if (swipedRow) {
              const revealBtn = swipedRow.querySelector('.jobs-row__delete-reveal');
              if (revealBtn) {
                revealBtn.removeAttribute('aria-hidden');
                revealBtn.tabIndex = 0;
              }
            }
          }
        }

        if (highlightId) {
          const card = document.getElementById('job-' + highlightId);
          if (card) {
            card.classList.add('jobs-card--highlighted');
          }
        }
      }
    }

    // Initial render & event bindings
    render();
    window.setInterval(render, 1000);
    window.addEventListener('storage', () => { lastDataSignature = ''; render(); });
    window.addEventListener('pose-jobs-change', () => { lastDataSignature = ''; render(); });
    window.addEventListener('pose-jobs-offline-change', () => { lastDataSignature = ''; render(); });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initJobsScreen);
  } else {
    initJobsScreen();
  }
})(window, document);
