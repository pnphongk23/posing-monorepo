/* docs/prototype/scripts/progress.js */
function initProgress() {
  const progressFill = document.querySelector('.nb-progress__fill');
  const progressLabel = document.getElementById('progress-percentage');
  const progressBar = document.querySelector('.nb-progress');

  if (progressFill && progressLabel) {
    const targetWidth = 78; // 78% target
    
    // Delayed start for visible loading effect
    setTimeout(() => {
      progressFill.style.width = `${targetWidth}%`;
      
      // Animate numerical count
      let currentVal = 0;
      const duration = 1500; // Matches CSS transition duration
      const startTime = performance.now();

      function animateCount(timestamp) {
        const elapsed = timestamp - startTime;
        const progress = Math.min(elapsed / duration, 1);
        
        // Easing function: cubic-out
        const easeVal = 1 - Math.pow(1 - progress, 3);
        currentVal = Math.floor(easeVal * targetWidth);
        
        progressLabel.textContent = `${currentVal}%`;
        if (progressBar) {
          progressBar.setAttribute('aria-valuenow', currentVal);
        }

        if (progress < 1) {
          requestAnimationFrame(animateCount);
        } else {
          progressLabel.textContent = `${targetWidth}%`;
          if (progressBar) {
            progressBar.setAttribute('aria-valuenow', targetWidth);
          }
        }
      }
      
      requestAnimationFrame(animateCount);
    }, 300);
  }
}
window.initProgress = initProgress;
