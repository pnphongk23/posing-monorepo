/* docs/prototype/scripts/guide-picker.js */
document.addEventListener('DOMContentLoaded', function() {
  const sheet = document.getElementById('pose-picker-sheet');
  const openButton = document.getElementById('camera-guide-btn');

  if (!sheet || !openButton) return;

  const panel = sheet.querySelector('.nb-pose-picker-panel');
  const closeButtons = sheet.querySelectorAll('[data-close-pose-picker]');
  const searchForm = document.getElementById('pose-picker-search-form');
  const searchInput = document.getElementById('pose-picker-search-input');
  const clearButton = document.getElementById('pose-picker-search-clear');
  const stateMessage = document.getElementById('pose-picker-state');
  const grid = document.getElementById('pose-picker-grid');
  const posePrototype = window.PosePrototype;
  const initialParams = new URLSearchParams(window.location.search);
  let query = initialParams.get('picker-q') || '';
  let forcedState = initialParams.get('picker-state') || 'ready';
  let closeTimer = null;

  function escapeHtml(value) {
    return posePrototype && typeof posePrototype.escapeHtml === 'function'
      ? posePrototype.escapeHtml(value)
      : String(value)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/\"/g, '&quot;')
        .replace(/'/g, '&#039;');
  }

  function getAvailablePoses() {
    if (!posePrototype || typeof posePrototype.getVisiblePoseFixtures !== 'function') return [];

    return posePrototype.getVisiblePoseFixtures().filter(pose => {
      return pose.category !== 'community' || pose.visibility === 'published';
    });
  }

    function setState(title, copy, tone, action) {
      if (!stateMessage) return;
      window.NBEmptyState.render(stateMessage, {
        action: action ? { label: action.label, onClick: action.onClick } : null,
        copy,
        state: tone,
        title
      });
    }

    function clearState() {
      if (!stateMessage) return;
      window.NBEmptyState.clear(stateMessage);
    }

  function updateSearchField() {
    if (searchInput) searchInput.value = query;
    if (clearButton) clearButton.hidden = !query.trim();
  }

  function updatePickerUrl() {
    const nextUrl = new URL(window.location.href);
    if (query.trim()) nextUrl.searchParams.set('picker-q', query.trim());
    else nextUrl.searchParams.delete('picker-q');
    nextUrl.searchParams.delete('picker-state');
    window.history.replaceState({}, '', nextUrl.href);
  }

  function createPosePickerCard(pose, index) {
    const item = document.createElement('div');
    const aspectClasses = ['nb-card--aspect-tall', 'nb-card--aspect-square', 'nb-card--aspect-short'];
    const card = document.createElement('button');
    const label = document.createElement('span');

    item.className = 'nb-grid-pose-item';
    card.type = 'button';
    card.className = `nb-card nb-card--pose-grid ${aspectClasses[index % aspectClasses.length]} u-w-full`;
    card.setAttribute('aria-label', `Use ${pose.title} pose`);
    card.dataset.poseId = pose.id;
    card.innerHTML = pose.svg;
    label.className = 'nb-grid-pose-label';
    label.textContent = pose.title;

    card.addEventListener('click', function() {
      const nextUrl = new URL('camera-live.html', window.location.href);
      nextUrl.searchParams.set('pose', pose.id);
      nextUrl.searchParams.set('source', pose.category === 'community' ? 'community' : 'my-poses');
      window.location.replace(nextUrl.href);
    });

    item.appendChild(card);
    item.appendChild(label);
    return item;
  }

  function render() {
    const availablePoses = getAvailablePoses();
    const searchTerm = query.trim().toLocaleLowerCase();
    const filteredPoses = availablePoses.filter(pose => {
      return !searchTerm || pose.title.toLocaleLowerCase().includes(searchTerm);
    });

    updateSearchField();
    clearState();
    if (grid) {
      grid.innerHTML = '';
      grid.hidden = false;
      grid.removeAttribute('aria-busy');
    }
    if (forcedState === 'loading') {
      if (grid) {
        grid.hidden = true;
        grid.setAttribute('aria-busy', 'true');
      }
        setState('Loading poses', 'Getting your pose library ready.', 'loading');
      return;
    }

      if (forcedState === 'error' || !posePrototype) {
        if (grid) grid.hidden = true;
        setState('Couldn’t load poses', 'Check your connection and try again.', 'error', {
        label: 'Try again',
        onClick: function() {
          forcedState = 'ready';
          render();
        }
      });
      return;
    }

      if (filteredPoses.length === 0) {
        if (grid) grid.hidden = true;
        const queryLabel = query.trim();
        setState(
          queryLabel ? `No poses match “${queryLabel}”` : 'No poses yet',
          queryLabel ? 'Try a different pose name.' : 'Create or save a pose to use it here.',
          'empty',
          null
        );
        return;
    }

    filteredPoses.forEach((pose, index) => {
      if (grid) grid.appendChild(createPosePickerCard(pose, index));
    });

      if (forcedState === 'offline') {
        setState('You’re offline', 'Showing your last available poses.', 'offline');
      }
  }

  function setOpen(isOpen) {
    window.clearTimeout(closeTimer);

    if (isOpen) {
      render();
      sheet.hidden = false;
      sheet.setAttribute('aria-hidden', 'false');
      openButton.setAttribute('aria-expanded', 'true');
      document.body.classList.add('is-pose-picker-open');
      window.requestAnimationFrame(function() {
        sheet.classList.add('is-open');
        const closeButton = document.getElementById('pose-picker-close');
        if (closeButton) closeButton.focus();
      });
      return;
    }

    sheet.classList.remove('is-open');
    sheet.setAttribute('aria-hidden', 'true');
    openButton.setAttribute('aria-expanded', 'false');
    document.body.classList.remove('is-pose-picker-open');
    const nextUrl = new URL(window.location.href);
    nextUrl.searchParams.delete('guide-picker');
    window.history.replaceState({}, '', nextUrl.href);
    closeTimer = window.setTimeout(function() {
      sheet.hidden = true;
    }, 250);
    openButton.focus();
  }

  openButton.addEventListener('click', function() {
    if (!openButton.disabled) setOpen(true);
  });

  closeButtons.forEach(function(button) {
    button.addEventListener('click', function() {
      setOpen(false);
    });
  });

  if (panel) {
    panel.addEventListener('click', function(event) {
      event.stopPropagation();
    });
  }

  if (searchInput) {
    searchInput.addEventListener('input', function() {
      query = searchInput.value;
      forcedState = 'ready';
      updatePickerUrl();
      render();
    });
  }

  if (clearButton) {
    clearButton.addEventListener('click', function() {
      query = '';
      forcedState = 'ready';
      updatePickerUrl();
      render();
      if (searchInput) searchInput.focus();
    });
  }

  if (searchForm) {
    searchForm.addEventListener('submit', function(event) {
      event.preventDefault();
      if (searchInput) searchInput.blur();
    });
  }

  document.addEventListener('keydown', function(event) {
    if (event.key === 'Escape' && !sheet.hidden) {
      event.preventDefault();
      setOpen(false);
    }
  });

  render();
  if (initialParams.get('guide-picker') === 'open') setOpen(true);
});
