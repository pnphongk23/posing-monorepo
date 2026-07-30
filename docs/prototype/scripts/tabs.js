/* docs/prototype/scripts/tabs.js */
function initTabs(onTabChange) {
  const tabs = document.querySelectorAll('.nb-tab-btn');

  tabs.forEach(tab => {
    tab.addEventListener('click', function() {
      // Toggle active states and accessibility state
      tabs.forEach(t => {
        t.classList.remove('is-active');
        t.setAttribute('aria-selected', 'false');
        
        // Handle aria-controls and panel visibility if specified
        const controls = t.getAttribute('aria-controls');
        if (controls) {
          const panel = document.getElementById(controls);
          if (panel) {
            panel.setAttribute('hidden', 'true');
          }
        }
      });
      
      this.classList.add('is-active');
      this.setAttribute('aria-selected', 'true');
      
      const controls = this.getAttribute('aria-controls');
      if (controls) {
        const panel = document.getElementById(controls);
        if (panel) {
          panel.removeAttribute('hidden');
        }
      }

      // Call callback with category
      if (typeof onTabChange === 'function') {
        const category = this.getAttribute('data-category');
        onTabChange(category);
      }
    });
  });
}
window.initTabs = initTabs;
