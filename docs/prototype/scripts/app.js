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

  // Initialize grid/list toggling on the gallery page
  if (typeof initViewToggle === 'function') {
    initViewToggle();
  }

  // --- SCREEN SPECIFIC LOGIC ---

  // 1. Poses List Screen Logic
  const posesGrid = document.getElementById('poses-dynamic-grid');
  const searchInput = document.getElementById('poses-search-input');
  
  if (posesGrid && typeof POSES_FIXTURES !== 'undefined') {
    let currentCategory = 'my-poses'; // default active tab matches screenshot
    let searchQuery = '';

    function renderPoses() {
      posesGrid.innerHTML = '';
      
      const filtered = POSES_FIXTURES.filter(pose => {
        const matchesTab = pose.category === currentCategory;
        const matchesSearch = pose.title.toLowerCase().includes(searchQuery.toLowerCase());
        return matchesTab && matchesSearch;
      });

      if (filtered.length === 0) {
        posesGrid.innerHTML = `
          <div class="u-text-center u-text-muted" style="grid-column: span 2; padding: var(--nb-space-xl) 0;">
            No poses found.
          </div>
        `;
        return;
      }

      filtered.forEach(pose => {
        // Create grid cell item
        const item = document.createElement('div');
        item.className = 'nb-grid-pose-item';
        
        let tagHtml = '';
        if (pose.tag) {
          tagHtml = `<span class="nb-card__tag nb-tag nb-tag--${pose.tagColor}">${pose.tag}</span>`;
        }

        let heartHtml = '';
        if (pose.hearts) {
          heartHtml = `
            <div class="nb-card__heart-badge">
              <svg style="width: 10px; height: 10px; stroke: currentColor; fill: currentColor;" viewBox="0 0 24 24">
                <path d="M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z"/>
              </svg>
              <span>${pose.hearts}</span>
            </div>
          `;
        } else {
          heartHtml = `
            <button class="nb-card__heart-badge-outline" aria-label="Like pose">
              <svg viewBox="0 0 24 24">
                <path d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z"/>
              </svg>
            </button>
          `;
        }

        item.innerHTML = `
          <a href="pose-detail.html?id=${pose.id}" class="nb-card nb-card--pose-grid u-w-full" aria-label="${pose.title} pose" style="text-decoration: none; color: inherit;">
            ${pose.svg}
            ${tagHtml}
            ${heartHtml}
          </a>
          <span class="nb-grid-pose-label">${pose.title}</span>
        `;

        // Bind heart outline toggle
        const heartBtn = item.querySelector('.nb-card__heart-badge-outline');
        if (heartBtn) {
          heartBtn.addEventListener('click', function(e) {
            e.preventDefault();
            e.stopPropagation();
            const svg = this.querySelector('svg');
            if (this.classList.toggle('is-liked')) {
              svg.style.fill = 'var(--nb-color-accent-pink)';
              svg.style.stroke = 'var(--nb-color-accent-pink)';
            } else {
              svg.style.fill = 'none';
              svg.style.stroke = 'var(--nb-color-gray)';
            }
          });
        }

        posesGrid.appendChild(item);
      });
    }

    // Initialize list tabs
    if (typeof initTabs === 'function') {
      initTabs(function(category) {
        currentCategory = category;
        renderPoses();
      });
    }

    // Initialize search listener
    if (searchInput) {
      searchInput.addEventListener('input', function(e) {
        searchQuery = e.target.value;
        renderPoses();
      });
    }

    // Initial render
    renderPoses();
  }

  // 2. Pose Detail Screen Logic
  const heartDetailBtn = document.getElementById('detail-heart-btn');
  const heartDetailCount = document.getElementById('detail-heart-count');
  
  if (heartDetailBtn && heartDetailCount) {
    heartDetailBtn.addEventListener('click', function() {
      const isLiked = this.classList.toggle('is-liked');
      let count = parseFloat(heartDetailCount.textContent);
      
      if (isLiked) {
        this.style.backgroundColor = 'var(--nb-color-accent-pink)';
        count += 0.1;
        heartDetailCount.textContent = count.toFixed(1) + 'K';
      } else {
        this.style.backgroundColor = '';
        count -= 0.1;
        heartDetailCount.textContent = count.toFixed(1) + 'K';
      }
    });
  }

  // Bookmark Toggle on Detail Page
  const bookmarkBtn = document.getElementById('detail-bookmark-btn');
  if (bookmarkBtn) {
    bookmarkBtn.addEventListener('click', function() {
      const isBookmarked = this.classList.toggle('is-active');
      const svg = this.querySelector('svg');
      if (isBookmarked) {
        svg.style.fill = 'var(--nb-color-accent-yellow)';
        svg.style.stroke = 'var(--nb-color-accent-yellow)';
      } else {
        svg.style.fill = 'none';
        svg.style.stroke = 'currentColor';
      }
    });
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

});
