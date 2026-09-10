/* docs/prototype/scripts/app.js */
document.addEventListener('DOMContentLoaded', function() {
  console.log('Neo-brutalist Pose App Initialized');

  // Check if loaded inside simulator iframe
  if (window.self !== window.top) {
    document.body.classList.add('is-iframe');
  }

  // Initialize general modal and dropdown bindings
  if (typeof initModals === 'function') {
    initModals();
  }

  // Initialize camera settings and grid toggles
  if (typeof initToggles === 'function') {
    initToggles();
  }

  // Initialize progress animation for extracting pose
  if (typeof initProgress === 'function') {
    initProgress();
  }

  // --- SCREEN SPECIFIC LOGIC ---

  const posePrototype = window.PosePrototype;
  const escapeHtml = posePrototype ? posePrototype.escapeHtml : value => String(value);
  const poseSourceLabel = posePrototype ? posePrototype.getPoseSourceLabel : pose => pose.category;

  function paywallUrl(returnPath) {
    return `paywall.html?return=${encodeURIComponent(returnPath)}`;
  }

  function createPoseCard(pose, index, origin) {
    const item = document.createElement('div');
    item.className = 'nb-grid-pose-item';

    const aspectClasses = ['nb-card--aspect-tall', 'nb-card--aspect-square', 'nb-card--aspect-short'];
    const aspectClass = aspectClasses[index % aspectClasses.length];
    const route = posePrototype ? posePrototype.getPoseRoute(pose, origin) : `pose-detail.html?id=${encodeURIComponent(pose.id)}`;

    item.innerHTML = `
      <a href="${route}" class="nb-card nb-card--pose-grid ${aspectClass} u-w-full" aria-label="${escapeHtml(pose.title)}" style="text-decoration: none; color: inherit;">
        ${pose.svg}
      </a>
      <span class="nb-grid-pose-label">${escapeHtml(pose.title)}</span>
    `;

    return item;
  }

  function setStateMessage(element, state, title, copy, action) {
    if (!element) return;

    element.className = `nb-state-message nb-state-message--${state}`;
    element.innerHTML = `<strong>${escapeHtml(title)}</strong><p>${escapeHtml(copy)}</p>`;

    if (action) {
      const actionButton = document.createElement('button');
      actionButton.type = 'button';
      actionButton.className = 'nb-btn nb-btn--white';
      actionButton.textContent = action.label;
      actionButton.addEventListener('click', action.onClick);
      element.appendChild(actionButton);
    }

    element.hidden = false;
  }

  function clearStateMessage(element) {
    if (!element) return;
    element.hidden = true;
    element.innerHTML = '';
  }

  // 1. Poses List Screen Logic
  const posesGrid = document.getElementById('poses-dynamic-grid');

  if (posesGrid && posePrototype) {
    const posesStateMessage = document.getElementById('poses-state-message');
    const posesCountLabel = document.getElementById('poses-count-label');
    const params = new URLSearchParams(window.location.search);
    let currentCategory = params.get('tab') === 'community' ? 'community' : 'my-poses';
    let forcedState = posePrototype.getPrototypeState();

    function updatePoseTabPresentation() {
      const activeTab = document.querySelector(`.nb-tab-btn[data-category="${currentCategory}"]`);

      document.querySelectorAll('.nb-tab-btn').forEach(tab => {
        const selected = tab === activeTab;
        tab.classList.toggle('is-active', selected);
        tab.setAttribute('aria-selected', String(selected));
      });
    }

    function getCurrentPoses() {
      return posePrototype.getVisiblePoseFixtures().filter(pose => {
        const isPublishedCommunity = pose.category !== 'community' || pose.visibility === 'published';
        return pose.category === currentCategory && isPublishedCommunity;
      });
    }

    function renderPoseCards(poses) {
      posesGrid.innerHTML = '';
      poses.forEach((pose, index) => posesGrid.appendChild(createPoseCard(pose, index, currentCategory === 'community' ? 'community' : 'personal')));
      posesGrid.hidden = false;
      posesGrid.removeAttribute('aria-busy');
      if (posesCountLabel) posesCountLabel.textContent = `${poses.length} ${poses.length === 1 ? 'pose' : 'poses'}`;
    }

    function renderPoses() {
      updatePoseTabPresentation();
      const currentPoses = getCurrentPoses();
      const isCommunity = currentCategory === 'community';

      if (forcedState === 'loading') {
        posesGrid.innerHTML = '<div class="nb-pose-loading" role="status">Loading poses…</div>';
        posesGrid.hidden = false;
        posesGrid.setAttribute('aria-busy', 'true');
        if (posesCountLabel) posesCountLabel.textContent = 'Loading';
        setStateMessage(posesStateMessage, 'loading', 'Loading poses', 'Hang on while we load your library.');
        return;
      }

      if (forcedState === 'error') {
        posesGrid.innerHTML = '';
        posesGrid.hidden = true;
        if (posesCountLabel) posesCountLabel.textContent = 'Unavailable';
        setStateMessage(posesStateMessage, 'error', 'Unable to load poses', 'Something went wrong. Try again.', {
          label: 'Retry',
          onClick: () => {
            forcedState = 'ready';
            renderPoses();
          }
        });
        return;
      }

      renderPoseCards(currentPoses);

      if (forcedState === 'refresh-error') {
        setStateMessage(posesStateMessage, 'error', 'Couldn’t refresh', 'Your current list is still here. Try again when you’re ready.', {
          label: 'Retry',
          onClick: () => {
            forcedState = 'ready';
            renderPoses();
          }
        });
        return;
      }

      if (forcedState === 'empty' || currentPoses.length === 0) {
        if (isCommunity) {
          setStateMessage(posesStateMessage, 'empty', 'No community poses yet', 'Check back later for new poses from the community.', {
            label: 'Retry',
            onClick: () => {
              forcedState = 'ready';
              renderPoses();
            }
          });
        } else {
          setStateMessage(posesStateMessage, 'empty', 'No poses yet', 'Capture a pose to start your library.', {
            label: 'Create a pose',
            onClick: () => { window.location.href = 'camera-live.html'; }
          });
        }
        posesGrid.hidden = true;
        if (posesCountLabel) posesCountLabel.textContent = 'Empty';
        return;
      }

      clearStateMessage(posesStateMessage);
    }

    if (typeof initTabs === 'function') {
      initTabs(function(category) {
        currentCategory = category === 'community' ? 'community' : 'my-poses';
        forcedState = 'ready';
        const nextUrl = new URL(window.location.href);
        nextUrl.searchParams.set('tab', currentCategory);
        nextUrl.searchParams.delete('state');
        window.history.replaceState({}, '', nextUrl);
        renderPoses();
      });
    }

    renderPoses();

    if (params.get('notice') === 'deleted') {
      setStateMessage(posesStateMessage, 'success', 'Pose deleted', 'Removed from My Poses.');
    }
  }

  // 2. Pose Detail Screen Logic
  const detailContent = document.getElementById('detail-content');
  const detailUnavailableState = document.getElementById('detail-unavailable-state');

  if (detailContent && posePrototype) {
    const params = new URLSearchParams(window.location.search);
    const requestedId = params.get('id') || 'dancing';
    const requestedSource = params.get('source') || (params.has('id') ? null : 'community');
    const forcedState = posePrototype.getPrototypeState();
    const pose = forcedState === 'unavailable'
      ? null
      : posePrototype.getPoseByReference(requestedId, requestedSource);
    const detailPageTitle = document.getElementById('detail-page-title');
    const detailPoseName = document.getElementById('detail-pose-name');
    const detailPoseSource = document.getElementById('detail-pose-source');
    const detailPoseContext = document.getElementById('detail-pose-context');
    const detailPoseSvg = document.getElementById('detail-pose-svg-container');
    const detailMetadata = document.getElementById('detail-metadata');
    const detailTryPoseBtn = document.getElementById('detail-try-pose-btn');
      const detailDeleteBtn = document.getElementById('detail-delete-btn');
      const confirmDeleteBtn = document.getElementById('confirm-delete-btn');
      const deleteModal = document.getElementById('delete-pose-modal');
      const detailReturnLink = document.getElementById('detail-return-link');
      const detailBackLink = document.getElementById('detail-back');

    function showDetailUnavailable() {
      detailContent.hidden = true;
      if (detailUnavailableState) {
        const copy = document.getElementById('detail-unavailable-copy');
        if (detailReturnLink) {
          detailReturnLink.href = requestedSource === 'community'
            ? 'poses-list.html?tab=community'
            : 'poses-list.html?tab=my-poses';
        }
        if (copy) {
          copy.textContent = requestedSource === 'community'
            ? 'This community pose could not be confirmed as published. Return to the Community tab and try again.'
            : 'This personal pose is no longer in My Poses. Return to the library to see the current list.';
        }
        detailUnavailableState.hidden = false;
      }
      if (detailPageTitle) detailPageTitle.textContent = 'Unavailable';
    }

    function appendMetadata(label, value) {
      if (value === null || value === undefined || value === '') return;
      const item = document.createElement('span');
      item.className = 'nb-tag nb-tag--pill';
      item.setAttribute('role', 'listitem');
      item.textContent = `${label}: ${value}`;
      detailMetadata.appendChild(item);
    }

    if (!pose || !pose.svg) {
      showDetailUnavailable();
    } else {
      const metadata = pose.metadata || {};
      const sourceLabel = poseSourceLabel(pose);

      if (detailPageTitle) detailPageTitle.textContent = pose.title;
      if (detailPoseName) detailPoseName.textContent = pose.title;
      if (detailPoseSource) {
        detailPoseSource.textContent = sourceLabel;
        detailPoseSource.classList.toggle('nb-tag--blue', pose.category === 'community');
        detailPoseSource.classList.toggle('nb-tag--green', pose.category !== 'community');
      }
        if (detailPoseContext) detailPoseContext.textContent = metadata.context || 'Metadata not provided';
        if (detailPoseSvg) detailPoseSvg.innerHTML = pose.svg;
        if (detailBackLink) {
          const searchOrigin = new URLSearchParams();
          if (params.get('q')) searchOrigin.set('q', params.get('q'));
          if (params.get('source')) searchOrigin.set('source', params.get('source'));
          const cameFromSearch = params.has('q');
          detailBackLink.href = cameFromSearch
            ? `search.html${searchOrigin.toString() ? `?${searchOrigin.toString()}` : ''}`
            : `poses-list.html?tab=${pose.category === 'community' ? 'community' : 'my-poses'}`;
          detailBackLink.setAttribute('aria-label', cameFromSearch ? 'Back to Search' : 'Back to pose library');
        }
        if (detailMetadata) {
        detailMetadata.innerHTML = '';
        appendMetadata('Author', metadata.author);
        appendMetadata('Difficulty', metadata.difficulty);
        appendMetadata('Tries', metadata.tries);
        appendMetadata('Saves', metadata.saves);
      }

      if (detailDeleteBtn) detailDeleteBtn.hidden = pose.category !== 'my-poses';

      if (detailTryPoseBtn) {
        detailTryPoseBtn.addEventListener('click', function() {
          const isPremium = sessionStorage.getItem('ai-pose.premium') === 'true';
          if (pose.category === 'community' && !isPremium) {
            const returnPath = `${window.location.pathname.split('/').pop()}${window.location.search}`;
            window.location.href = paywallUrl(returnPath);
            return;
          }
          const overlayUrl = new URL('camera-pose-overlay.html', window.location.href);
          overlayUrl.searchParams.set('id', pose.id);
          if (pose.source || pose.category) {
            overlayUrl.searchParams.set('source', pose.source || pose.category);
          }
          window.location.href = overlayUrl.pathname + overlayUrl.search;
        });
      }

      if (confirmDeleteBtn) {
        confirmDeleteBtn.addEventListener('click', function() {
          if (pose.category !== 'my-poses' || !posePrototype.markPoseDeleted(pose.id)) return;

          confirmDeleteBtn.disabled = true;
          if (deleteModal) {
            const closeButton = deleteModal.querySelector('[data-close-modal]');
            if (closeButton) closeButton.click();
          }
          window.location.href = 'poses-list.html?tab=my-poses&notice=deleted';
        });
      }
    }
  }

  // 3. Camera state and capture feedback
  const shutterBtn = document.getElementById('shutter-btn');
  const cameraViewport = document.getElementById('camera-feed');
  const cameraStatus = document.getElementById('camera-status');
  const cameraShutterLabel = document.getElementById('camera-shutter-label');
  const galleryThumb = document.getElementById('camera-gallery-thumb');
  const permissionOverlay = document.getElementById('camera-permission-state');
  const permissionAction = document.getElementById('camera-permission-action');
    const cameraSettingsBtn = document.getElementById('camera-settings-btn');
      const cameraZoomBtn = document.getElementById('camera-zoom-btn');
      const cameraZoomSlider = document.getElementById('camera-zoom-slider');
    const cameraFlipBtn = document.getElementById('camera-flip-btn');
    const cameraGuideBtn = document.querySelector('.nb-camera-guide-chip');
    const cameraShutterDefaultLabel = shutterBtn
      ? shutterBtn.getAttribute('aria-label') || 'Capture photo'
      : 'Capture photo';
    const cameraState = new URLSearchParams(window.location.search).get('state');

  function setCameraStatus(message, tone, hideAfter) {
    if (!cameraStatus) return;
    cameraStatus.textContent = message;
    cameraStatus.dataset.tone = tone || 'success';
    cameraStatus.hidden = false;
    window.clearTimeout(cameraStatus._hideTimer);
    if (hideAfter) {
      cameraStatus._hideTimer = window.setTimeout(() => {
        cameraStatus.hidden = true;
      }, hideAfter);
    }
  }

  function setCameraUnavailable(isUnavailable) {
    if (permissionOverlay) permissionOverlay.hidden = !isUnavailable;
      [shutterBtn, cameraSettingsBtn, cameraZoomBtn, cameraZoomSlider, cameraFlipBtn, cameraGuideBtn, galleryThumb].forEach(control => {
      if (!control) return;
      control.disabled = isUnavailable;
      control.setAttribute('aria-disabled', String(isUnavailable));
    });
    if (shutterBtn) shutterBtn.classList.toggle('is-disabled', isUnavailable);
  }

  if (cameraViewport) {
    if (cameraState === 'permission-denied') {
      setCameraUnavailable(true);
    } else if (cameraState === 'loading') {
      cameraViewport.dataset.cameraState = 'loading';
      setCameraStatus('Starting camera…', 'info');
    } else if (cameraState === 'error') {
      setCameraStatus('We could not save that photo. Try again.', 'error');
    }
  }

  if (permissionAction) {
    permissionAction.addEventListener('click', function() {
      setCameraStatus('Open your device Settings to allow camera access.', 'info');
    });
  }

  if (galleryThumb) {
    galleryThumb.addEventListener('click', function() {
      if (galleryThumb.disabled) return;
      window.location.href = 'gallery.html';
    });
  }

  if (shutterBtn && cameraViewport) {
    let captureInFlight = false;
    shutterBtn.addEventListener('click', function() {
      if (captureInFlight || shutterBtn.disabled) return;
      if (sessionStorage.getItem('ai-pose.premium') !== 'true') {
        window.location.href = paywallUrl('camera-live.html');
        return;
      }

        captureInFlight = true;
        shutterBtn.disabled = true;
        shutterBtn.classList.add('is-busy');
        shutterBtn.setAttribute('aria-busy', 'true');
        shutterBtn.setAttribute('aria-label', 'Saving photo');
        if (cameraStatus) cameraStatus.hidden = true;
        if (cameraShutterLabel) cameraShutterLabel.textContent = 'Saving…';

        window.setTimeout(() => {
          captureInFlight = false;
          shutterBtn.disabled = false;
          shutterBtn.classList.remove('is-busy');
          shutterBtn.removeAttribute('aria-busy');
          shutterBtn.setAttribute('aria-label', cameraShutterDefaultLabel);
          if (cameraShutterLabel) cameraShutterLabel.textContent = cameraShutterDefaultLabel;
          if (galleryThumb) {
            galleryThumb.style.backgroundImage = cameraViewport.style.backgroundImage;
            galleryThumb.setAttribute('aria-label', 'Open Gallery, latest captured photo');
            galleryThumb.classList.add('is-new');
          }
        }, 600);
    });
  }

  // 4. Gallery Screen Logic
    const galleryGrid = document.getElementById('gallery-grid');

    if (galleryGrid && typeof GALLERY_FIXTURES !== 'undefined') {
      const galleryGroups = [
        { key: 'today', label: 'Today', daysAgo: 0, photos: GALLERY_FIXTURES.today },
        { key: 'yesterday', label: 'Yesterday', daysAgo: 1, photos: GALLERY_FIXTURES.yesterday }
      ];
      function dateKeyForDaysAgo(daysAgo) {
        const date = new Date();
        date.setHours(12, 0, 0, 0);
        date.setDate(date.getDate() - daysAgo);
        return date.toISOString().slice(0, 10);
      }

      const galleryItems = galleryGroups.flatMap(group => group.photos.map(photo => ({
        photo,
        dateLabel: group.label,
        daysAgo: group.daysAgo,
        dateKey: dateKeyForDaysAgo(group.daysAgo)
      })));
      const filterButtons = document.querySelectorAll('[data-gallery-filter]');
      const dateInput = document.getElementById('gallery-date-input');
      const dateFilterLabel = document.querySelector('[data-gallery-filter-label="custom"]');
      const validFilters = new Set(['all', 'today', 'week', 'month', 'custom']);
      const params = new URLSearchParams(window.location.search);
      let galleryFilter = validFilters.has(params.get('filter')) ? params.get('filter') : 'all';
      let galleryDate = /^\d{4}-\d{2}-\d{2}$/.test(params.get('date') || '') ? params.get('date') : '';
      if (galleryFilter === 'custom' && !galleryDate) galleryFilter = 'all';
      if (dateInput) dateInput.value = galleryDate;

      function getVisibleGalleryItems(filter = galleryFilter) {
        return galleryItems.filter(item => {
          if (filter === 'today') return item.daysAgo === 0;
          if (filter === 'week') return item.daysAgo < 7;
          if (filter === 'month') return item.daysAgo < 30;
          if (filter === 'custom') return item.dateKey === galleryDate;
          return true;
        });
      }

      function formatGalleryDate(dateValue) {
        if (!dateValue) return 'Date';
        return new Intl.DateTimeFormat('en-US', {month: 'short', day: 'numeric'}).format(new Date(`${dateValue}T12:00:00`));
      }

      function syncGalleryFilterControls() {
        filterButtons.forEach(button => {
          const isActive = button.dataset.galleryFilter === galleryFilter;
          button.classList.toggle('is-active', isActive);
          button.setAttribute('aria-pressed', isActive ? 'true' : 'false');
        });
        if (dateFilterLabel) dateFilterLabel.textContent = galleryFilter === 'custom' ? formatGalleryDate(galleryDate) : 'Date';
      }

      function syncGalleryUrl() {
        const nextParams = new URLSearchParams(window.location.search);
        if (galleryFilter === 'all') nextParams.delete('filter');
        else nextParams.set('filter', galleryFilter);
        if (galleryFilter === 'custom' && galleryDate) nextParams.set('date', galleryDate);
        else nextParams.delete('date');
        nextParams.delete('view');
        const query = nextParams.toString();
        window.history.replaceState({}, '', `${window.location.pathname}${query ? `?${query}` : ''}`);
      }

      function renderGallery() {
        galleryGrid.innerHTML = '';

        const visiblePhotos = getVisibleGalleryItems();
        const visibleCount = visiblePhotos.length;

        if (visibleCount === 0) {
          galleryGrid.innerHTML = `
            <p class="nb-gallery-empty u-text-center u-text-muted" role="status">No photos in this filter yet.</p>
          `;
          return;
        }

        const leadStaggerIndex = visiblePhotos.length > 1 ? Math.ceil(visiblePhotos.length / 2) : -1;
        visiblePhotos.forEach(({photo, dateLabel}, photoIndex) => {
          const item = document.createElement('div');
          item.className = 'nb-gallery-item';
            const detailParams = new URLSearchParams({
              id: photo.id,
              filter: galleryFilter
            });
            if (galleryFilter === 'custom' && galleryDate) detailParams.set('date', galleryDate);
            const detailHref = `gallery-detail-v2.html?${detailParams.toString()}`;
          const photoStyle = photo.photoUrl ? ` style="background-image: url('${photo.photoUrl}');"` : '';
          const staggerClass = photoIndex === leadStaggerIndex
            ? 'nb-gallery-item__media--square'
            : ['nb-gallery-item__media--tall', 'nb-gallery-item__media--square', 'nb-gallery-item__media--wide'][photoIndex % 3];
          const tag = photo.tag ? `<span class="nb-gallery-item__tag">${escapeHtml(photo.tag)}</span>` : '';
          const placeholder = photo.placeholder
            ? '<svg class="nb-gallery-item__placeholder" aria-hidden="true"><use href="#icon-image"></use></svg>'
            : '';

          item.innerHTML = `
            <a href="${detailHref}" class="nb-gallery-item__link" aria-label="${escapeHtml(photo.title)}, ${escapeHtml(dateLabel)} at ${escapeHtml(photo.time)}">
              <span class="nb-gallery-item__media ${staggerClass}${photo.placeholder ? ' nb-gallery-item__media--placeholder' : ''}"${photoStyle}>${placeholder}</span>
              <span class="nb-gallery-item__meta">
                <strong class="nb-gallery-item__title">${escapeHtml(photo.title)}</strong>
                <span class="nb-gallery-item__details">${tag}<span>${escapeHtml(photo.time)}</span></span>
              </span>
            </a>
          `;
          galleryGrid.appendChild(item);
        });
      }

      filterButtons.forEach(button => {
        button.addEventListener('click', () => {
          if (button.dataset.galleryFilter === 'custom') {
            if (dateInput) {
              if (typeof dateInput.showPicker === 'function') dateInput.showPicker();
              else {
                dateInput.focus();
                dateInput.click();
              }
            }
            return;
          }
          galleryFilter = button.dataset.galleryFilter;
          galleryDate = '';
          syncGalleryFilterControls();
          renderGallery();
          syncGalleryUrl();
        });
      });

      if (dateInput) {
        dateInput.addEventListener('change', () => {
          if (!dateInput.value) return;
          galleryDate = dateInput.value;
          galleryFilter = 'custom';
          syncGalleryFilterControls();
          renderGallery();
          syncGalleryUrl();
        });
      }

      syncGalleryFilterControls();
      renderGallery();
      syncGalleryUrl();
    }

  // 4b. Gallery Detail Screen Logic
  const galleryDetailScreen = document.getElementById('gallery-detail-screen');

  if (galleryDetailScreen && typeof GALLERY_FIXTURES !== 'undefined') {
    const allPhotos = [...GALLERY_FIXTURES.today, ...GALLERY_FIXTURES.yesterday];
    const params = new URLSearchParams(window.location.search);
    const photo = allPhotos.find(item => item.id === params.get('id'));
    const unavailableState = document.getElementById('gallery-unavailable-state');
    const detailContent = document.getElementById('gallery-detail-content');
    const detailPhoto = document.getElementById('gallery-detail-photo');
    const detailTitle = document.getElementById('gallery-detail-title');
    const detailActions = document.getElementById('gallery-detail-actions');
    const detailNotice = document.getElementById('gallery-detail-notice');
    const saveBtn = document.getElementById('gallery-save-btn');
    const confirmDeleteBtn = document.getElementById('confirm-delete-photo-btn');
    const canOpen = photo && !photo.placeholder && photo.photoUrl;

    if (!canOpen) {
      if (detailContent) detailContent.hidden = true;
      if (detailActions) detailActions.hidden = true;
      if (unavailableState) unavailableState.hidden = false;
      if (detailTitle) detailTitle.textContent = 'Unavailable';
    } else {
      if (unavailableState) unavailableState.hidden = true;
      if (detailContent) detailContent.hidden = false;
      if (detailTitle) detailTitle.textContent = photo.title;
      if (detailPhoto) {
        detailPhoto.style.backgroundImage = `url('${photo.photoUrl}')`;
        detailPhoto.setAttribute('aria-label', photo.title);
      }

      if (saveBtn && detailNotice) {
        saveBtn.addEventListener('click', function() {
          const isPremium = sessionStorage.getItem('ai-pose.premium') === 'true';
          if (!isPremium) {
            const returnPath = `${window.location.pathname.split('/').pop()}${window.location.search}`;
            window.location.href = paywallUrl(returnPath);
            return;
          }
          detailNotice.textContent = 'Saved to Photos.';
          detailNotice.hidden = false;
        });
      }

      if (confirmDeleteBtn) {
        confirmDeleteBtn.addEventListener('click', function() {
          window.location.href = 'gallery.html';
        });
      }
    }
  }

  // 5. Camera Close Button Logic
  const closeBtn = document.getElementById('camera-close-btn');
  if (closeBtn) {
    closeBtn.addEventListener('click', function() {
      if (document.referrer && document.referrer.includes(window.location.host)) {
        window.history.back();
      } else {
        window.location.href = 'poses-list.html';
      }
    });
  }

    // 6. Search Screen Logic
    const searchResultsGrid = document.getElementById('search-results-grid');
    const searchScreenInput = document.getElementById('search-screen-input');
    const searchClearBtn = document.getElementById('search-clear-btn');
    const searchForm = document.getElementById('search-form');
    const searchDiscovery = document.getElementById('search-discovery');
    const searchResultsPanel = document.getElementById('search-results-panel');

    if (searchResultsGrid && posePrototype) {
        const searchStateMessage = document.getElementById('search-state-message');
      const searchResultsCount = document.getElementById('search-results-count');
      const searchResultsHeading = document.getElementById('search-results-heading');
      const searchParams = new URLSearchParams(window.location.search);
      const validSources = new Set(['all', 'my-poses', 'community']);
      let searchQuery = searchParams.get('q') || '';
      let searchSource = validSources.has(searchParams.get('source')) ? searchParams.get('source') : 'all';
      let forcedState = posePrototype.getPrototypeState();

      function getAvailablePoses() {
        return posePrototype.getVisiblePoseFixtures().filter(pose => {
          return pose.category !== 'community' || pose.visibility === 'published';
        });
      }

      function getSearchResults() {
        const queryLower = searchQuery.trim().toLocaleLowerCase();
        return getAvailablePoses().filter(pose => {
          const matchesSource = searchSource === 'all' || pose.category === searchSource;
          const matchesQuery = !queryLower || pose.title.toLocaleLowerCase().includes(queryLower);
          return matchesSource && matchesQuery;
        });
      }

      function updateSourceControls() {
        document.querySelectorAll('.nb-search-filter').forEach(button => {
          const isActive = button.dataset.searchSource === searchSource;
          button.classList.toggle('is-active', isActive);
          button.setAttribute('aria-pressed', String(isActive));
        });

      }

      function updateUrl() {
        const nextUrl = new URL(window.location.href);
        if (searchQuery.trim()) nextUrl.searchParams.set('q', searchQuery.trim());
        else nextUrl.searchParams.delete('q');
        if (searchSource !== 'all') nextUrl.searchParams.set('source', searchSource);
        else nextUrl.searchParams.delete('source');
        nextUrl.searchParams.delete('state');
        window.history.replaceState({}, '', nextUrl);
      }

      function updateSearchField() {
        if (searchScreenInput) searchScreenInput.value = searchQuery;
        if (searchClearBtn) searchClearBtn.hidden = !searchQuery.trim();
      }

      function clearSearch() {
        searchQuery = '';
        forcedState = 'ready';
        updateSearchField();
        updateUrl();
        renderSearchResults();
        if (searchScreenInput) searchScreenInput.focus();
      }

      function setQuery(value) {
        searchQuery = value;
        forcedState = 'ready';
        updateSearchField();
        updateUrl();
        renderSearchResults();
      }

      function setSource(source) {
        if (!validSources.has(source)) return;
        searchSource = source;
        forcedState = 'ready';
        updateSourceControls();
        updateUrl();
        renderSearchResults();
      }

      function renderSearchResults() {
        const sourceLabel = searchSource === 'my-poses' ? 'My poses' : searchSource === 'community' ? 'Community' : '';
        const hasSearchIntent = Boolean(searchQuery.trim()) || searchSource !== 'all' || forcedState !== 'ready';

        updateSourceControls();

        if (searchDiscovery) searchDiscovery.hidden = hasSearchIntent;
        if (searchResultsPanel) searchResultsPanel.hidden = !hasSearchIntent;
        if (!hasSearchIntent) {
          clearStateMessage(searchStateMessage);
          searchResultsGrid.innerHTML = '';
          searchResultsGrid.hidden = false;
          searchResultsGrid.removeAttribute('aria-busy');
          return;
        }

        if (searchResultsHeading) {
          searchResultsHeading.textContent = searchQuery.trim()
            ? `Results for “${searchQuery.trim()}”`
            : sourceLabel || 'Results';
        }

        if (forcedState === 'loading') {
          searchResultsGrid.innerHTML = '<div class="nb-pose-loading" role="status">Searching the library…</div>';
          searchResultsGrid.setAttribute('aria-busy', 'true');
          if (searchResultsCount) searchResultsCount.textContent = 'Searching…';
          setStateMessage(searchStateMessage, 'loading', 'Searching', 'Looking through your library and the community.');
          return;
        }

        if (forcedState === 'error') {
          searchResultsGrid.innerHTML = '';
          searchResultsGrid.hidden = true;
          searchResultsGrid.removeAttribute('aria-busy');
          if (searchResultsCount) searchResultsCount.textContent = 'Unavailable';
          setStateMessage(searchStateMessage, 'error', 'Search is paused', 'We could not load results right now. Your query is still here.', {
            label: 'Try again',
            onClick: () => {
              forcedState = 'ready';
              renderSearchResults();
            }
          });
          return;
        }

        const filtered = forcedState === 'empty' ? [] : getSearchResults();
        const isOffline = forcedState === 'offline';
        searchResultsGrid.innerHTML = '';
        searchResultsGrid.hidden = false;
        searchResultsGrid.removeAttribute('aria-busy');

        if (searchResultsCount) {
          const resultLabel = `${filtered.length} ${filtered.length === 1 ? 'pose' : 'poses'}`;
          searchResultsCount.textContent = `${resultLabel}${sourceLabel ? ` · ${sourceLabel}` : ''}`;
        }

        if (filtered.length === 0) {
          const emptyTitle = searchQuery.trim() ? 'No close matches' : 'Nothing here yet';
          const emptyCopy = searchQuery.trim()
            ? `Try a shorter title, or browse another source.`
            : `There are no poses in ${sourceLabel.toLocaleLowerCase() || 'this library'} yet.`;
          setStateMessage(searchStateMessage, 'empty', emptyTitle, emptyCopy, {
            label: searchQuery.trim() ? 'Clear search' : 'Show all poses',
            onClick: searchQuery.trim() ? clearSearch : () => setSource('all')
          });
          searchResultsGrid.hidden = true;
          return;
        }

        filtered.forEach((pose, index) => {
          const card = createPoseCard(pose, index, 'search');
          const link = card.querySelector('a');
          if (link) {
            const route = new URL(link.href, window.location.href);
            if (searchQuery.trim()) route.searchParams.set('q', searchQuery.trim());
            if (searchSource !== 'all') route.searchParams.set('source', searchSource);
            link.href = route.href;
          }
          searchResultsGrid.appendChild(card);
        });
        if (isOffline) {
          setStateMessage(searchStateMessage, 'success', 'Offline library', 'Showing the last confirmed pose list. Community results may be out of date.');
        } else {
          clearStateMessage(searchStateMessage);
        }
      }

      updateSearchField();

      if (searchScreenInput) {
        searchScreenInput.addEventListener('input', function() {
          setQuery(searchScreenInput.value);
        });
        window.setTimeout(() => searchScreenInput.focus(), 100);
      }

      if (searchClearBtn) searchClearBtn.addEventListener('click', clearSearch);

      if (searchForm) {
        searchForm.addEventListener('submit', function(event) {
          event.preventDefault();
          if (searchScreenInput) searchScreenInput.blur();
          renderSearchResults();
        });
      }

      document.querySelectorAll('[data-search-query]').forEach(button => {
        button.addEventListener('click', () => setQuery(button.dataset.searchQuery || ''));
      });

      document.querySelectorAll('[data-search-source]').forEach(button => {
        button.addEventListener('click', () => setSource(button.dataset.searchSource || 'all'));
      });

      renderSearchResults();
    }

});
