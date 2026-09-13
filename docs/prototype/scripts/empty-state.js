/* docs/prototype/scripts/empty-state.js */
(function (window, document) {
  const STATE_NAMES = ['empty', 'error', 'loading', 'offline', 'success', 'warning'];
  const ROLE_BY_STATE = {
    error: 'alert',
    empty: 'status',
    loading: 'status',
    offline: 'status',
    success: 'status',
    warning: 'status'
  };
  const LIVE_BY_STATE = {
    error: 'assertive',
    empty: 'polite',
    loading: 'polite',
    offline: 'polite',
    success: 'polite',
    warning: 'polite'
  };

  function resolveTarget(target) {
    if (typeof target === 'string') return document.querySelector(target);
    return target;
  }

  function removeStateClasses(element) {
    Array.from(element.classList).forEach(className => {
      if (className.indexOf('nb-empty-state--') === 0 || className.indexOf('nb-state-message--') === 0) {
        element.classList.remove(className);
      }
    });
  }

  function createAction(action) {
    if (!action || !action.label) return null;

    const control = action.href ? document.createElement('a') : document.createElement('button');
    control.className = action.className || 'nb-btn nb-btn--white';
    control.textContent = action.label;

    if (control.tagName === 'BUTTON') {
      control.type = 'button';
    } else {
      control.href = action.href;
    }

    if (typeof action.onClick === 'function') {
      control.addEventListener('click', action.onClick);
    }

    return control;
  }

  function render(target, options) {
    const element = resolveTarget(target);
    if (!element) return null;

    const settings = options || {};
    const state = STATE_NAMES.includes(settings.state) ? settings.state : 'empty';

    removeStateClasses(element);
    element.classList.add('nb-empty-state', `nb-empty-state--${state}`);
    element.setAttribute('role', settings.role || ROLE_BY_STATE[state]);
    element.setAttribute('aria-live', settings.live || LIVE_BY_STATE[state]);
    element.setAttribute('aria-atomic', 'true');
    const visual = settings.preserveVisual ? element.querySelector('[data-empty-state-visual]') : null;
    element.replaceChildren();

    if (visual) element.appendChild(visual);

    if (settings.title) {
      const title = document.createElement('strong');
      title.className = 'nb-empty-state__title';
      title.textContent = settings.title;
      element.appendChild(title);
    }

    if (settings.copy) {
      const copy = document.createElement('p');
      copy.className = 'nb-empty-state__copy';
      copy.textContent = settings.copy;
      element.appendChild(copy);
    }

    const action = createAction(settings.action);
    if (action) element.appendChild(action);

    element.hidden = false;
    return element;
  }

  function clear(target) {
    const element = resolveTarget(target);
    if (!element) return null;

    element.hidden = true;
    element.replaceChildren();
    return element;
  }

  if (window.customElements && !window.customElements.get('nb-empty-state')) {
    window.customElements.define('nb-empty-state', class extends window.HTMLElement {
      connectedCallback() {
        this.classList.add('nb-empty-state');
      }
    });
  }

  window.NBEmptyState = { clear, render };
})(window, document);
