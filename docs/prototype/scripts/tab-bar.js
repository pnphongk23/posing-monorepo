/* docs/prototype/scripts/tab-bar.js */
(function () {
  const TABS = [
    { id: 'poses', label: 'Poses', href: 'poses-list.html', icon: 'icon-grid' },
    { id: 'gallery', label: 'Gallery', href: 'gallery.html', icon: 'icon-image' },
  ];

  function renderTabBar(activeId) {
    const phone = document.querySelector('.nb-phone');
    if (!phone || phone.querySelector('.nb-dock')) return;

    phone.classList.add('nb-phone--with-tab-bar');

    // Create floating dock element
    const dock = document.createElement('nav');
    dock.className = 'nb-dock';
    dock.setAttribute('aria-label', 'Main navigation');

    dock.innerHTML = `
      <div class="nb-dock__pill">
        ${TABS.map(function (tab) {
          const isActive = tab.id === activeId;
          return `
              <a href="${tab.href}" class="nb-dock__item${isActive ? ' is-active' : ''}"${isActive ? ' aria-current="page"' : ''} aria-label="${tab.label}" title="${tab.label}">
                <svg viewBox="0 0 24 24" aria-hidden="true"><use href="#${tab.icon}"></use></svg>
              </a>
          `;
        }).join('')}
      </div>
      <a href="camera-live.html" class="nb-dock__camera-btn nb-btn nb-btn--circle nb-btn--pink" aria-label="Open Camera">
        <svg><use href="#icon-camera"></use></svg>
      </a>
    `;

    phone.appendChild(dock);
  }

  window.initTabBar = function (activeId) {
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', function () {
        renderTabBar(activeId);
      });
    } else {
      renderTabBar(activeId);
    }
  };
})();
