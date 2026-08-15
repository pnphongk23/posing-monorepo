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

  function createPoseCard(pose, index) {
    const item = document.createElement('div');
    item.className = 'nb-grid-pose-item';

    const aspectClasses = ['nb-card--aspect-tall', 'nb-card--aspect-short', 'nb-card--aspect-square'];
    const aspectClass = aspectClasses[index % aspectClasses.length];
    const sourceLabel = poseSourceLabel(pose);
    const sourceClass = pose.category === 'community' ? 'nb-card__source-badge--community' : 'nb-card__source-badge--personal';
    const route = posePrototype ? posePrototype.getPoseRoute(pose) : `pose-detail.html?id=${encodeURIComponent(pose.id)}`;

    item.innerHTML = `
      <a href="${route}" class="nb-card nb-card--pose-grid ${aspectClass} u-w-full" aria-label="${escapeHtml(pose.title)} · ${escapeHtml(sourceLabel)}" style="text-decoration: none; color: inherit;">
        <span class="nb-card__source-badge nb-tag ${sourceClass}">${escapeHtml(sourceLabel)}</span>
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
    const posesCategoryLabel = document.getElementById('poses-category-label');
    const posesSourceNote = document.getElementById('poses-source-note');
    const posesRefreshBtn = document.getElementById('poses-refresh-btn');
    const params = new URLSearchParams(window.location.search);
    let currentCategory = params.get('tab') === 'community' ? 'community' : 'my-poses';
    let forcedState = posePrototype.getPrototypeState();
    let isRefreshing = false;

    function updatePoseTabPresentation() {
      const isCommunity = currentCategory === 'community';
      const activeTab = document.querySelector(`.nb-tab-btn[data-category="${currentCategory}"]`);

      document.querySelectorAll('.nb-tab-btn').forEach(tab => {
        const selected = tab === activeTab;
        tab.classList.toggle('is-active', selected);
        tab.setAttribute('aria-selected', String(selected));
      });

      if (posesCategoryLabel) posesCategoryLabel.textContent = isCommunity ? 'Community' : 'My Poses';
      if (posesSourceNote) {
        posesSourceNote.textContent = isCommunity
          ? 'Published mock catalogue · management unavailable'
          : 'Private mock poses · delete available';
      }
    }

    function getCurrentPoses() {
      return posePrototype.getVisiblePoseFixtures().filter(pose => {
        const isPublishedCommunity = pose.category !== 'community' || pose.visibility === 'published';
        return pose.category === currentCategory && isPublishedCommunity;
      });
    }

    function renderPoseCards(poses) {
      posesGrid.innerHTML = '';
      poses.forEach((pose, index) => posesGrid.appendChild(createPoseCard(pose, index)));
      posesGrid.hidden = false;
      posesGrid.removeAttribute('aria-busy');
      if (posesCountLabel) posesCountLabel.textContent = `${poses.length} ${poses.length === 1 ? 'pose' : 'poses'}`;
    }

    function renderPoses() {
      updatePoseTabPresentation();
      const currentPoses = getCurrentPoses();
      const isCommunity = currentCategory === 'community';

      if (forcedState === 'loading') {
        posesGrid.innerHTML = '<div class="nb-pose-loading" role="status">Loading mock poses…</div>';
        posesGrid.hidden = false;
        posesGrid.setAttribute('aria-busy', 'true');
        if (posesCountLabel) posesCountLabel.textContent = 'Loading';
        setStateMessage(posesStateMessage, 'loading', 'Loading pose library', 'The prototype is loading confirmed mock results.');
        return;
      }

      if (forcedState === 'error') {
        posesGrid.innerHTML = '';
        posesGrid.hidden = true;
        if (posesCountLabel) posesCountLabel.textContent = 'Unavailable';
        setStateMessage(posesStateMessage, 'error', 'Unable to load poses', 'No unconfirmed pose is shown. Retry the mock catalogue request.', {
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
        setStateMessage(posesStateMessage, 'error', 'Refresh failed', 'The confirmed list is still shown. Retry when you are ready.', {
          label: 'Retry refresh',
          onClick: () => {
            forcedState = 'ready';
            renderPoses();
          }
        });
        return;
      }

      if (forcedState === 'empty' || currentPoses.length === 0) {
        if (isCommunity) {
          setStateMessage(posesStateMessage, 'empty', 'No published community poses', 'The mock catalogue has no confirmed community results right now.', {
            label: 'Retry catalogue',
            onClick: () => {
              forcedState = 'ready';
              renderPoses();
            }
          });
        } else {
          setStateMessage(posesStateMessage, 'empty', 'No poses saved yet', 'Capture a pose to start building My Poses.', {
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

    if (posesRefreshBtn) {
      posesRefreshBtn.addEventListener('click', function() {
        if (isRefreshing) return;
        isRefreshing = true;
        posesRefreshBtn.disabled = true;
        posesGrid.setAttribute('aria-busy', 'true');
        setStateMessage(posesStateMessage, 'loading', 'Refreshing mock catalogue', 'Confirmed results stay visible while the prototype refreshes.');

        window.setTimeout(function() {
          isRefreshing = false;
          posesRefreshBtn.disabled = false;
          forcedState = 'ready';
          renderPoses();
        }, 300);
      });
    }

    renderPoses();

    if (params.get('notice') === 'deleted') {
      setStateMessage(posesStateMessage, 'success', 'Pose deleted', 'Removed from My Poses for this prototype session.');
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
    const detailHandoffNote = document.getElementById('detail-handoff-note');
    const detailDeleteBtn = document.getElementById('detail-delete-btn');
    const confirmDeleteBtn = document.getElementById('confirm-delete-btn');
    const deleteModal = document.getElementById('delete-pose-modal');
    const detailReturnLink = document.getElementById('detail-return-link');

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
          if (detailHandoffNote) {
            detailHandoffNote.textContent = `Prepared “${pose.title}” for the Camera handoff (mock). Camera overlay and controls remain deferred to the pending handoff phase.`;
            detailHandoffNote.hidden = false;
          }
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

  // 3. Shutter Click Flash Simulation
  const shutterBtn = document.getElementById('shutter-btn');
  const cameraViewport = document.getElementById('camera-feed');

  if (shutterBtn && cameraViewport) {
    shutterBtn.addEventListener('click', function(e) {
      // Simulate physical flash card blink
      const flash = document.createElement('div');
      flash.style.position = 'absolute';
      flash.style.top = '0';
      flash.style.left = '0';
      flash.style.width = '100%';
      flash.style.height = '100%';
      flash.style.backgroundColor = '#FFFFFF';
      flash.style.opacity = '1';
      flash.style.transition = 'opacity 0.25s ease';
      flash.style.zIndex = '999';
      cameraViewport.appendChild(flash);

      // Sound feedback (if supported, silent fallback)
      try {
        const audioCtx = new (window.AudioContext || window.webkitAudioContext)();
        const osc = audioCtx.createOscillator();
        const gain = audioCtx.createGain();
        osc.connect(gain);
        gain.connect(audioCtx.destination);
        osc.frequency.value = 1000;
        gain.gain.setValueAtTime(0.1, audioCtx.currentTime);
        gain.gain.exponentialRampToValueAtTime(0.01, audioCtx.currentTime + 0.1);
        osc.start();
        osc.stop(audioCtx.currentTime + 0.1);
      } catch (err) {}

      // Fade out flash and redirect to Extracting screen
      setTimeout(() => {
        flash.style.opacity = '0';
        setTimeout(() => {
          window.location.href = 'camera-extracting.html';
        }, 150);
      }, 50);
    });
  }

  // 4. Gallery Screen Logic
  const galleryGrid = document.getElementById('gallery-grid');

  if (galleryGrid && typeof GALLERY_FIXTURES !== 'undefined') {
    // Combine today and yesterday into one continuous list
    const allPhotos = [...GALLERY_FIXTURES.today, ...GALLERY_FIXTURES.yesterday];
    let gallerySearchQuery = '';

    function renderGallery() {
      galleryGrid.innerHTML = '';

      const filtered = allPhotos.filter(photo => {
        const queryLower = gallerySearchQuery.toLowerCase();
        const titleMatch = photo.title.toLowerCase().includes(queryLower);
        const tagMatch = photo.tag ? photo.tag.toLowerCase().includes(queryLower) : false;
        return titleMatch || tagMatch;
      });

      if (filtered.length === 0) {
        galleryGrid.innerHTML = `
          <div class="u-text-center u-text-muted" style="grid-column: span 3; padding: var(--nb-space-xl) 0; width: 100%;">
            No photos found.
          </div>
        `;
        return;
      }

      filtered.forEach(photo => {
        const item = document.createElement('div');
        item.className = 'nb-grid-photo-item';

        if (photo.placeholder) {
          item.innerHTML = `
            <div class="nb-card nb-card--gallery-dense nb-card--placeholder" role="img" aria-label="Photo unavailable">
              <svg class="nb-card__placeholder-icon"><use href="#icon-image"></use></svg>
            </div>
          `;
        } else {
          item.innerHTML = `
            <div class="nb-card nb-card--gallery-dense" style="background-image: url('${photo.photoUrl}');" role="img" aria-label="${photo.title}"></div>
          `;
        }
        galleryGrid.appendChild(item);
      });
    }

    // Search listener removed (plumbing moved to dedicated search screen)

    renderGallery();
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

  if (searchResultsGrid && posePrototype) {
    const searchStateMessage = document.getElementById('search-state-message');
    const searchResultsCount = document.getElementById('search-results-count');
    const searchParams = new URLSearchParams(window.location.search);
    let searchQuery = searchParams.get('q') || '';
    let forcedState = posePrototype.getPrototypeState();

    function getSearchResults() {
      const queryLower = searchQuery.trim().toLocaleLowerCase();
      return posePrototype.getVisiblePoseFixtures().filter(pose => {
        const isPublishedCommunity = pose.category !== 'community' || pose.visibility === 'published';
        return isPublishedCommunity && pose.title.toLocaleLowerCase().includes(queryLower);
      });
    }

    function clearSearch() {
      searchQuery = '';
      if (searchScreenInput) {
        searchScreenInput.value = '';
        searchScreenInput.focus();
      }
      if (searchClearBtn) searchClearBtn.style.display = 'none';
      forcedState = 'ready';
      renderSearchResults();
    }

    function renderSearchResults() {
      const queryLabel = searchQuery.trim() ? ` for “${searchQuery.trim()}”` : '';

      if (forcedState === 'loading') {
        searchResultsGrid.innerHTML = '<div class="nb-pose-loading" role="status">Loading mock search results…</div>';
        searchResultsGrid.setAttribute('aria-busy', 'true');
        if (searchResultsCount) searchResultsCount.querySelector('span').textContent = 'Loading';
        setStateMessage(searchStateMessage, 'loading', 'Searching mock catalogue', 'Community title search is represented by deterministic fixture data.');
        return;
      }

      if (forcedState === 'error') {
        searchResultsGrid.innerHTML = '';
        searchResultsGrid.hidden = true;
        if (searchResultsCount) searchResultsCount.querySelector('span').textContent = 'Unavailable';
        setStateMessage(searchStateMessage, 'error', 'Search unavailable', 'The mock catalogue could not confirm results. Retry without changing your title.', {
          label: 'Retry search',
          onClick: () => {
            forcedState = 'ready';
            renderSearchResults();
          }
        });
        return;
      }

      const filtered = forcedState === 'empty' ? [] : getSearchResults();
      searchResultsGrid.innerHTML = '';
      searchResultsGrid.hidden = false;
      searchResultsGrid.removeAttribute('aria-busy');

      if (searchResultsCount) {
        searchResultsCount.querySelector('span').textContent = `${filtered.length} ${filtered.length === 1 ? 'mock pose' : 'mock poses'}${queryLabel}`;
      }

      if (filtered.length === 0) {
        const emptyCopy = searchQuery.trim()
          ? `No pose titles match “${searchQuery.trim()}”. Clear the title to browse the fixture catalogue.`
          : 'No confirmed mock poses are available to search right now.';
        setStateMessage(searchStateMessage, 'empty', 'No matching poses', emptyCopy, {
          label: 'Clear search',
          onClick: clearSearch
        });
        searchResultsGrid.hidden = true;
        return;
      }

      filtered.forEach((pose, index) => searchResultsGrid.appendChild(createPoseCard(pose, index)));
      clearStateMessage(searchStateMessage);
    }

    if (searchScreenInput) {
      searchScreenInput.value = searchQuery;
      searchScreenInput.addEventListener('input', function() {
        searchQuery = searchScreenInput.value;
        forcedState = 'ready';
        if (searchClearBtn) searchClearBtn.style.display = searchQuery ? 'inline-flex' : 'none';
        const nextUrl = new URL(window.location.href);
        if (searchQuery) nextUrl.searchParams.set('q', searchQuery);
        else nextUrl.searchParams.delete('q');
        nextUrl.searchParams.delete('state');
        window.history.replaceState({}, '', nextUrl);
        renderSearchResults();
      });

      window.setTimeout(() => searchScreenInput.focus(), 100);
    }

    if (searchClearBtn) {
      searchClearBtn.style.display = searchQuery ? 'inline-flex' : 'none';
      searchClearBtn.addEventListener('click', clearSearch);
    }

    renderSearchResults();
  }

});
