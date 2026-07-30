/* docs/prototype/scripts/tab-bar.js */
(function () {
  const TABS = [
    { id: 'poses', label: 'Poses', href: 'poses-list.html', icon: 'icon-grid' },
    { id: 'camera', label: 'Camera', href: 'camera-live.html', icon: 'icon-camera' },
    { id: 'gallery', label: 'Gallery', href: 'gallery.html', icon: 'icon-image' },
  ];

  function renderTabBar(activeId) {
    const phone = document.querySelector('.nb-phone');
    if (!phone || phone.querySelector('.nb-tab-bar')) return;

    phone.classList.add('nb-phone--with-tab-bar');

    const nav = document.createElement('nav');
    nav.className = 'nb-tab-bar';
    nav.setAttribute('aria-label', 'Main navigation');

    nav.innerHTML = TABS.map(function (tab) {
      const isActive = tab.id === activeId;
      return (
        '<a href="' + tab.href + '" class="nb-tab-bar__item' + (isActive ? ' is-active' : '') + '"' +
        (isActive ? ' aria-current="page"' : '') + '>' +
        '<svg viewBox="0 0 24 24"><use href="#' + tab.icon + '"></use></svg>' +
        '<span>' + tab.label + '</span></a>'
      );
    }).join('');

    phone.appendChild(nav);
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
