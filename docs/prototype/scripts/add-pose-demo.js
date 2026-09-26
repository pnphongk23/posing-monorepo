(function () {
  'use strict';

  const $ = id => document.getElementById(id);
  const form = $('add-pose-form');
  const fileInput = $('library-source');
  const nameInput = $('pose-name');
  const tagsInput = $('pose-tags');
  const descriptionInput = $('pose-description');
  const query = new URLSearchParams(location.search);
  let imageUrl = '';
  let photoName = '';
  let busy = false;

  function error(fieldId, messageId, message) {
    const field = $(fieldId);
    const control = field.querySelector('input, textarea');
    field.setAttribute('aria-invalid', String(Boolean(message)));
    if (control) control.setAttribute('aria-invalid', String(Boolean(message)));
    $(messageId).textContent = message;
    $(messageId).hidden = !message;
  }

  function validate() {
    const tags = tagsInput.value.split(',').map(value => value.trim()).filter(Boolean);
    error('image-field', 'image-error', imageUrl ? '' : 'Choose a photo from your Photo Library.');
    error('name-field', 'name-error', nameInput.value.trim() ? '' : 'Add a name for this pose.');
    error('tags-field', 'tags-error', tags.length ? '' : 'Add at least one tag.');
    const first = !imageUrl ? fileInput : !nameInput.value.trim() ? nameInput : !tags.length ? tagsInput : null;
    if (first) first.focus();
    return !first;
  }

  function preview(url, filename, alt) {
    imageUrl = url;
    photoName = filename;
    $('image-field').classList.add('has-image');
    $('image-source-title').textContent = 'Change photo';
    $('image-preview-img').src = url;
    $('image-preview-img').alt = alt;
    $('image-preview-caption').textContent = filename;
    $('processing-image').src = url;
    $('processing-image').alt = alt;
    $('processing-image-caption').textContent = filename;
    $('image-preview').hidden = false;
    error('image-field', 'image-error', '');
  }

  function demoPhoto() {
    const svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 480 320"><rect width="480" height="320" fill="#f5e9d7"/><circle cx="240" cy="72" r="26" fill="#e89cae" stroke="#121212" stroke-width="5"/><path d="M240 100v93m0-65-65-35m65 35 65-35m-65 100-50 85m50-85 50 85" stroke="#121212" stroke-width="10" fill="none"/><text x="24" y="295" font-family="sans-serif" font-size="18">SAMPLE PHOTO</text></svg>';
    preview('data:image/svg+xml;charset=UTF-8,' + encodeURIComponent(svg), 'Sample pose photo', 'Illustrated sample pose photo');
    nameInput.value = 'Window-light portrait';
    tagsInput.value = 'Portrait, Window light';
  }

  fileInput.addEventListener('change', () => {
    const file = fileInput.files && fileInput.files[0];
    if (!file) return;
    if (!file.type.startsWith('image/')) {
      error('image-field', 'image-error', 'Choose an image file to continue.');
      return;
    }
    if (imageUrl.startsWith('blob:')) URL.revokeObjectURL(imageUrl);
    preview(URL.createObjectURL(file), file.name || 'Selected photo', 'Selected pose photo preview');
  });
  nameInput.addEventListener('input', () => { if (nameInput.value.trim()) error('name-field', 'name-error', ''); });
  tagsInput.addEventListener('input', () => { if (tagsInput.value.split(',').some(value => value.trim())) error('tags-field', 'tags-error', ''); });

  function showProcessing(job) {
    $('form-fields').disabled = true;
    $('create-pose').disabled = true;
    form.hidden = true;
    $('add-pose-action-bar').hidden = true;
    $('add-pose-nav').hidden = true;
    $('add-pose-intro').hidden = true;
    $('prototype-note').hidden = true;
    $('processing-screen').hidden = false;
    $('processing-title').textContent = 'Processing';
    $('processing-copy').textContent = 'You can leave this screen at any time. Processing continues in the background.';
    $('flow-progress').hidden = false;
    const jobId = job && (job.id || job.localId);
    if (jobId) {
      $('processing-view-jobs').href = 'jobs.html?from=add-pose&job=' + encodeURIComponent(jobId);
    } else {
      $('processing-view-jobs').href = 'jobs.html?from=add-pose';
    }
    $('processing-title').focus();
  }

  form.addEventListener('submit', event => {
    event.preventDefault();
    if (busy || !validate()) return;
    if (!navigator.onLine || query.get('state') === 'offline') {
      $('flow-title').textContent = 'You’re offline';
      $('flow-copy').textContent = 'Your details are still here. Reconnect, then submit again.';
      $('flow-feedback').dataset.state = 'offline';
      $('flow-feedback').hidden = false;
      return;
    }
    busy = true;
    let job = null;
    if (window.PoseJobsDemo && typeof window.PoseJobsDemo.create === 'function') {
      job = PoseJobsDemo.create({
        name: nameInput.value.trim(),
        tags: tagsInput.value.split(',').map(value => value.trim()).filter(Boolean),
        description: descriptionInput.value.trim(),
        photoName
      }, query.get('state') === 'failure' ? 'extract-failed' : '');
    }
    showProcessing(job);
  });

  if (['selected', 'validation', 'processing', 'failure', 'offline'].includes(query.get('state'))) demoPhoto();
  if (query.get('state') === 'validation') {
    nameInput.value = '';
    tagsInput.value = '';
    validate();
  }
  if (query.get('state') === 'processing') {
    showProcessing({ id: 'demo-job' });
  }
  if (query.get('state') === 'offline') {
    $('flow-title').textContent = 'You’re offline';
    $('flow-copy').textContent = 'Your details are still here. Reconnect, then submit again.';
    $('flow-feedback').dataset.state = 'offline';
    $('flow-feedback').hidden = false;
  }
})();
