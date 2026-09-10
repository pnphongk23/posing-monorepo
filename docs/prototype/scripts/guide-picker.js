/* docs/prototype/scripts/guide-picker.js */
document.addEventListener('DOMContentLoaded', function() {
  document.querySelectorAll('[data-select-guide]').forEach(function(link) {
    link.addEventListener('click', function(event) {
      event.preventDefault();
      window.location.replace(link.href);
    });
  });
});
