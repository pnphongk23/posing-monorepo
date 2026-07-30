/* docs/prototype/scripts/button-press.js */
(function() {
  document.addEventListener('DOMContentLoaded', function() {
    const buttons = document.querySelectorAll('.nb-btn');
    
    buttons.forEach(button => {
      // Add keyboard support to active visual states
      button.addEventListener('keydown', function(e) {
        if (e.key === ' ' || e.key === 'Enter') {
          this.classList.add('is-active');
        }
      });

      button.addEventListener('keyup', function(e) {
        if (e.key === ' ' || e.key === 'Enter') {
          this.classList.remove('is-active');
        }
      });

      // Accessible feedback log
      button.addEventListener('click', function() {
        console.log(`Button Pressed: ${this.textContent.trim() || this.getAttribute('aria-label') || 'Icon Button'}`);
      });
    });
  });
})();
