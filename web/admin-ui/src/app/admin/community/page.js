'use client';

import { useCallback, useEffect, useState } from 'react';
import { Upload, Plus, X, RefreshCw, Pencil, Trash2, Check } from 'lucide-react';
import NavButton from '@/components/NavButton';
import ActionButton from '@/components/ActionButton';

const STATUS_BADGE = {
  local: 'bg-accent-yellow',
  published: 'bg-accent-green',
};
const DEFAULT_OWNER_ACCOUNT_ID = '00000000-0000-0000-0000-000000000001';

const COMMUNITY_ADMIN_API = '/api/admin/community/poses';

async function parseResponse(response) {
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    const message =
      payload.error?.message ||
      payload.error ||
      payload.message ||
      `Request failed (${response.status})`;
    throw new Error(message);
  }
  return payload;
}

function normalizeList(raw) {
  return String(raw || '')
    .split(',')
    .map((item) => item.trim())
    .filter(Boolean);
}

export default function AdminCommunityPage() {
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [imagePreview, setImagePreview] = useState('');
  const [form, setForm] = useState({
    name: '',
    tags: '',
    description: '',
    status: 'local',
    ownerAccountId: DEFAULT_OWNER_ACCOUNT_ID,
  });
  const [selectedFile, setSelectedFile] = useState(null);
  const [poses, setPoses] = useState([]);
  const [loadingPoses, setLoadingPoses] = useState(false);
  const [listError, setListError] = useState('');

  // Edit modal state
  const [selectedPose, setSelectedPose] = useState(null);
  const [editingForm, setEditingForm] = useState(null);
  const [saving, setSaving] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const [editError, setEditError] = useState('');
  const [editNotice, setEditNotice] = useState('');

  const fetchPoses = useCallback(async () => {
    setLoadingPoses(true);
    setListError('');
    try {
      const res = await fetch(`${COMMUNITY_ADMIN_API}?limit=100`, {
        cache: 'no-store',
      });
      const payload = await res.json().catch(() => ({}));
      if (!res.ok) {
        throw new Error(
          payload.error?.message || payload.error || payload.message || `Request failed (${res.status})`
        );
      }
      setPoses(payload.data ?? []);
    } catch (err) {
      setListError(err.message);
    } finally {
      setLoadingPoses(false);
    }
  }, []);

  useEffect(() => { fetchPoses(); }, [fetchPoses]);

  const handleImageChange = useCallback((e) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setSelectedFile(file);
    setForm((prev) => ({ ...prev, name: file.name.replace(/\.[^/.]+$/, '') }));
    const reader = new FileReader();
    reader.onload = (event) => setImagePreview(event.target?.result || '');
    reader.readAsDataURL(file);
  }, []);

  const handleClearImage = useCallback(() => {
    setSelectedFile(null);
    setImagePreview('');
  }, []);

  const submitForm = useCallback(async () => {
    if (!selectedFile) { setError('Vui lòng chọn hình ảnh.'); return; }
    if (!form.name.trim()) { setError('Vui lòng nhập tên pose.'); return; }
    if (!form.ownerAccountId.trim()) { setError('ownerAccountId là bắt buộc.'); return; }

    setSubmitting(true);
    setError('');
    setNotice('Đang chạy extraction...');

    try {
      const extractForm = new FormData();
      extractForm.append('image', selectedFile);
      const extractResponse = await fetch('/api/admin/extract-pose', { method: 'POST', body: extractForm });
      const extractPayload = await parseResponse(extractResponse);
      const jobId = extractPayload.data?.jobId;
      if (!jobId) throw new Error('Extraction did not return jobId.');

      let job;
      for (let attempt = 0; attempt < 60; attempt += 1) {
        const jobResponse = await fetch(`/api/admin/extract-jobs/${jobId}`, { cache: 'no-store' });
        const jobPayload = await parseResponse(jobResponse);
        job = jobPayload.data;
        if (job.status === 'succeeded' || job.status === 'failed') break;
        await new Promise((resolve) => setTimeout(resolve, 1000));
      }
      if (!job || job.status !== 'succeeded') throw new Error('Extraction did not succeed.');

      const response = await fetch(COMMUNITY_ADMIN_API, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          jobId,
          ownerAccountId: form.ownerAccountId.trim(),
          name: form.name.trim(),
          tags: normalizeList(form.tags),
          description: form.description.trim() || null,
          bodyParts: ['full-body'],
          difficulty: null,
        }),
      });
      await parseResponse(response);
      setNotice('Đã extraction và tạo Pose thành công.');
      setForm({ name: '', tags: '', description: '', status: 'local', ownerAccountId: DEFAULT_OWNER_ACCOUNT_ID });
      setSelectedFile(null);
      setImagePreview('');
      fetchPoses();
    } catch (err) {
      setError(err.message);
    } finally {
      setSubmitting(false);
    }
  }, [form, selectedFile, fetchPoses]);

  const openEdit = useCallback((pose) => {
    setSelectedPose(pose);
    setEditingForm({
      name: pose.name || '',
      tags: Array.isArray(pose.tags) ? pose.tags.join(', ') : '',
      description: pose.description ?? '',
      status: pose.status || 'local',
    });
    setEditError('');
    setEditNotice('');
  }, []);

  const closeEdit = useCallback(() => {
    setSelectedPose(null);
    setEditingForm(null);
    setSaving(false);
    setDeleting(false);
    setEditError('');
    setEditNotice('');
  }, []);

  const updateEditing = useCallback((field, value) => {
    setEditingForm((prev) => ({ ...prev, [field]: value }));
  }, []);

  const savePose = useCallback(async () => {
    if (!editingForm) return;
    if (!editingForm.name.trim()) { setEditError('Vui lòng nhập tên pose.'); return; }

    setSaving(true);
    setEditError('');
    setEditNotice('');

    try {
      const response = await fetch(`${COMMUNITY_ADMIN_API}/${selectedPose.poseId}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          name: editingForm.name.trim(),
          tags: normalizeList(editingForm.tags),
          description: editingForm.description.trim() || null,
          status: editingForm.status,
        }),
      });

      const payload = await parseResponse(response);
      setSelectedPose(payload.data ?? selectedPose);
      setEditNotice('Đã lưu thay đổi thành công.');
      fetchPoses();
    } catch (err) {
      setEditError(err.message);
    } finally {
      setSaving(false);
    }
  }, [editingForm, selectedPose, fetchPoses]);

  const deletePose = useCallback(async () => {
    if (!selectedPose) return;
    if (!window.confirm(`Bạn có chắc chắn xóa pose "${selectedPose.name}"? Hành động này không thể hoàn tác.`)) {
      return;
    }

    setDeleting(true);
    setEditError('');
    setEditNotice('');

    try {
      const response = await fetch(`${COMMUNITY_ADMIN_API}/${selectedPose.poseId}`, {
        method: 'DELETE',
      });
      await parseResponse(response);
      const deletedName = selectedPose.name;
      closeEdit();
      setNotice(`Đã xóa pose "${deletedName}".`);
      fetchPoses();
    } catch (err) {
      setEditError(err.message);
      setDeleting(false);
    }
  }, [selectedPose, closeEdit, fetchPoses]);

  return (
    <div className="min-h-screen bg-bg flex flex-col">
      {/* Header */}
      <div className="flex items-center gap-3 px-6 py-4 border-b-2 border-black">
        <NavButton />
        <h1 className="text-xl font-extrabold tracking-neo uppercase">Admin — Community Poses</h1>
      </div>

      {/* Main: 2-column layout */}
      <div className="flex flex-1 gap-6 p-6 items-start">

        {/* LEFT: Upload Form — fixed width */}
        <div className="w-80 flex-shrink-0">
          <div className="rounded-2xl neo-border bg-white p-5 neo-shadow-md">
            <div className="text-[13px] font-extrabold tracking-neo-wide uppercase mb-4">
              Upload Pose
            </div>

            <div className="flex flex-col gap-3">
              {/* Image */}
              <div className="rounded-xl neo-border bg-gray-50">
                {imagePreview ? (
                  <div className="relative p-2">
                    <img src={imagePreview} alt="Preview" className="w-full h-48 object-contain rounded-lg" />
                    <button
                      onClick={handleClearImage}
                      className="absolute top-3 right-3 rounded-lg neo-border bg-accent-pink p-1.5 neo-press"
                    >
                      <X size={12} />
                    </button>
                  </div>
                ) : (
                  <label className="flex flex-col items-center justify-center h-32 cursor-pointer">
                    <Upload size={20} className="mb-2 opacity-40" />
                    <span className="text-[11px] font-bold opacity-60">Chọn hình ảnh</span>
                    <input type="file" accept="image/*" onChange={handleImageChange} className="hidden" />
                  </label>
                )}
              </div>

              <input
                value={form.name}
                onChange={(e) => setForm((p) => ({ ...p, name: e.target.value }))}
                placeholder="Pose name *"
                className="w-full px-3 py-2 rounded-xl neo-border text-[12px] font-medium focus:outline-none"
              />
              <input
                value={form.tags}
                onChange={(e) => setForm((p) => ({ ...p, tags: e.target.value }))}
                placeholder="Tags (comma-separated)"
                className="w-full px-3 py-2 rounded-xl neo-border text-[12px] font-medium focus:outline-none"
              />
              <textarea
                value={form.description}
                onChange={(e) => setForm((p) => ({ ...p, description: e.target.value }))}
                placeholder="Description"
                rows={3}
                className="w-full px-3 py-2 rounded-xl neo-border text-[12px] font-medium focus:outline-none resize-none"
              />
              <input
                value={form.ownerAccountId}
                onChange={(e) => setForm((p) => ({ ...p, ownerAccountId: e.target.value }))}
                placeholder="Owner account UUID *"
                className="w-full px-3 py-2 rounded-xl neo-border text-[12px] font-medium focus:outline-none"
              />
              <select
                value={form.status}
                onChange={(e) => setForm((p) => ({ ...p, status: e.target.value }))}
                className="w-full px-3 py-2 rounded-xl neo-border text-[12px] font-medium"
              >
                <option value="draft">DRAFT</option>
                <option value="published">PUBLISHED</option>
              </select>

              {error && (
                <div className="rounded-xl neo-border bg-accent-pink px-3 py-2 text-[11px] font-bold">
                  {error}
                </div>
              )}
              {notice && (
                <div className="rounded-xl neo-border bg-accent-green px-3 py-2 text-[11px] font-bold">
                  {notice}
                </div>
              )}

              <ActionButton onClick={submitForm} icon={Plus} bg="bg-accent-yellow" disabled={submitting}>
                {submitting ? 'UPLOADING...' : 'UPLOAD POSE'}
              </ActionButton>
            </div>
          </div>
        </div>

        {/* RIGHT: Pose List — fills remaining space */}
        <div className="flex-1 min-w-0">
          <div className="rounded-2xl neo-border bg-white p-5 neo-shadow-md">
            <div className="flex items-center justify-between mb-4">
              <div className="text-[13px] font-extrabold tracking-neo-wide uppercase">
                All Poses
                <span className="ml-2 text-[11px] font-bold opacity-50">({poses.length})</span>
              </div>
              <button
                onClick={fetchPoses}
                disabled={loadingPoses}
                className="rounded-xl neo-border bg-gray-100 px-3 py-1.5 neo-press disabled:opacity-50 flex items-center gap-1.5 text-[11px] font-bold"
              >
                <RefreshCw size={11} className={loadingPoses ? 'animate-spin' : ''} />
                REFRESH
              </button>
            </div>

            {listError ? (
              <div className="rounded-xl neo-border bg-accent-pink px-3 py-3 text-[11px] font-bold">
                <div className="mb-2">Không tải được danh sách pose: {listError}</div>
                <button
                  onClick={fetchPoses}
                  className="rounded-lg neo-border bg-white px-3 py-1.5 neo-press text-[11px] font-bold"
                >
                  THỬ LẠI
                </button>
              </div>
            ) : loadingPoses && poses.length === 0 ? (
              <div className="text-[12px] font-bold opacity-40 text-center py-16">Loading...</div>
            ) : poses.length === 0 ? (
              <div className="text-[12px] font-bold opacity-40 text-center py-16">Chưa có pose nào</div>
            ) : (
              <div className="grid grid-cols-2 xl:grid-cols-3 2xl:grid-cols-4 gap-3">
                {poses.map((pose) => (
                  <div
                    key={pose.poseId}
                    onClick={() => openEdit(pose)}
                    className="rounded-xl neo-border bg-gray-50 overflow-hidden group cursor-pointer hover:shadow-md transition-shadow"
                    role="button"
                    tabIndex={0}
                    onKeyDown={(e) => {
                      if (e.key === 'Enter' || e.key === ' ') {
                        e.preventDefault();
                        openEdit(pose);
                      }
                    }}
                  >
                    {/* Image */}
                    <div className="aspect-square bg-gray-100 overflow-hidden relative">
                      {pose.skeletonUrl ? (
                        <img
                          src={pose.skeletonUrl}
                          alt={pose.name}
                          className="w-full h-full object-cover"
                        />
                      ) : (
                        <div className="w-full h-full flex items-center justify-center opacity-20">
                          <Upload size={24} />
                        </div>
                      )}
                      <span className="absolute top-2 right-2 rounded-lg neo-border bg-white p-1.5 opacity-0 group-hover:opacity-100 transition-opacity" title="Edit pose">
                        <Pencil size={11} />
                      </span>
                    </div>

                    {/* Info */}
                    <div className="p-2">
                      <div className="text-[12px] font-extrabold truncate mb-1">{pose.name}</div>
                      <div className="flex items-center gap-1 flex-wrap">
                        <span className={`text-[9px] font-bold px-1.5 py-0.5 rounded-md neo-border ${STATUS_BADGE[pose.status] ?? 'bg-gray-100'}`}>
                          {pose.status?.toUpperCase()}
                        </span>
                        <span className="text-[9px] font-bold opacity-40 ml-auto">↓{pose.downloadCount ?? 0}</span>
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
      </div>

      {/* EDIT MODAL */}
      {selectedPose && editingForm && (
        <div
          className="fixed inset-0 z-50 bg-black/50 flex items-center justify-center p-4"
          onClick={closeEdit}
        >
          <div
            className="w-full max-w-lg max-h-[90vh] overflow-y-auto rounded-2xl neo-border bg-white p-5 neo-shadow-lg"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center justify-between mb-3">
              <div className="text-[13px] font-extrabold tracking-neo-wide uppercase">
                Edit Pose
              </div>
              <button
                onClick={closeEdit}
                className="rounded-lg neo-border bg-gray-100 p-1.5 neo-press"
                title="Close"
              >
                <X size={14} />
              </button>
            </div>

            <div className="rounded-xl neo-border bg-gray-50 overflow-hidden mb-3">
              {selectedPose.skeletonUrl ? (
                <img
                  src={selectedPose.skeletonUrl}
                  alt={selectedPose.name}
                  className="w-full h-40 object-contain bg-gray-100"
                />
              ) : (
                <div className="w-full h-40 flex items-center justify-center opacity-20">
                  <Upload size={24} />
                </div>
              )}
            </div>

            <div className="flex flex-col gap-3">
              <input
                value={editingForm.name}
                onChange={(e) => updateEditing('name', e.target.value)}
                placeholder="Pose name *"
                className="w-full px-3 py-2 rounded-xl neo-border text-[12px] font-medium focus:outline-none"
              />
              <input
                value={editingForm.tags}
                onChange={(e) => updateEditing('tags', e.target.value)}
                placeholder="Tags (comma-separated)"
                className="w-full px-3 py-2 rounded-xl neo-border text-[12px] font-medium focus:outline-none"
              />
              <textarea
                value={editingForm.description}
                onChange={(e) => updateEditing('description', e.target.value)}
                placeholder="Description"
                rows={3}
                className="w-full px-3 py-2 rounded-xl neo-border text-[12px] font-medium focus:outline-none resize-none"
              />
              <select
                value={editingForm.status}
                onChange={(e) => updateEditing('status', e.target.value)}
                className="w-full px-3 py-2 rounded-xl neo-border text-[12px] font-medium"
              >
                <option value="draft">DRAFT</option>
                <option value="published">PUBLISHED</option>
              </select>
            </div>

            {editError && (
              <div className="rounded-xl neo-border bg-accent-pink px-3 py-2 text-[11px] font-bold mt-3">
                {editError}
              </div>
            )}
            {editNotice && (
              <div className="rounded-xl neo-border bg-accent-green px-3 py-2 text-[11px] font-bold mt-3">
                {editNotice}
              </div>
            )}

            <div className="flex gap-2 mt-4">
              <div className="flex-1">
                <ActionButton
                  onClick={savePose}
                  icon={Check}
                  bg="bg-accent-yellow"
                  disabled={saving || deleting}
                >
                  {saving ? 'SAVING...' : 'SAVE'}
                </ActionButton>
              </div>
              <button
                onClick={deletePose}
                disabled={saving || deleting}
                className="flex items-center justify-center gap-2 rounded-xl neo-border bg-accent-pink px-4 py-3 neo-shadow-md neo-press font-bold text-[13px] tracking-neo disabled:opacity-50"
              >
                <Trash2 size={14} />
                {deleting ? 'DELETING...' : 'DELETE'}
              </button>
              <button
                onClick={closeEdit}
                disabled={saving || deleting}
                className="rounded-xl neo-border bg-gray-100 px-4 py-3 neo-press font-bold text-[13px] tracking-neo disabled:opacity-50"
              >
                CANCEL
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}