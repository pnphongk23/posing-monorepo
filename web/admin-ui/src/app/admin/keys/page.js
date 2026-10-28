'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { RefreshCcw, Shield, Trash2, Plus, Cpu } from 'lucide-react';
import NavButton from '@/components/NavButton';
import ActionButton from '@/components/ActionButton';

const STATUS_OPTIONS = ['active', 'disabled', 'exhausted'];

const PROVIDER_OPTIONS = [
  { id: 'gemini_native', label: 'Gemini Native' },
  { id: 'higgsfield_cli', label: 'Higgsfield CLI' },
];

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

export default function AdminKeysPage() {
  const [keys, setKeys] = useState([]);
  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [form, setForm] = useState({ name: '', apiKey: '' });
  const [provider, setProvider] = useState('higgsfield_cli');
  const [providerLoading, setProviderLoading] = useState(true);
  const [providerSaving, setProviderSaving] = useState(false);
  const [providerError, setProviderError] = useState('');
  const [providerNotice, setProviderNotice] = useState('');

  const activeCount = useMemo(
    () => keys.filter((key) => key.status === 'active').length,
    [keys]
  );

  const fetchProvider = useCallback(async () => {
    setProviderLoading(true);
    setProviderError('');
    try {
      const response = await fetch('/api/admin/settings/extraction-provider', {
        cache: 'no-store',
      });
      const payload = await parseResponse(response);
      setProvider(payload.data?.provider || 'higgsfield_cli');
    } catch (err) {
      setProviderError(err.message);
    } finally {
      setProviderLoading(false);
    }
  }, []);

  const saveProvider = useCallback(async () => {
    setProviderSaving(true);
    setProviderError('');
    setProviderNotice('');
    try {
      const response = await fetch('/api/admin/settings/extraction-provider', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ provider }),
      });
      const payload = await parseResponse(response);
      setProvider(payload.data?.provider || provider);
      setProviderNotice('Đã lưu extract engine. Áp dụng cho job được claim sau khi lưu.');
    } catch (err) {
      setProviderError(err.message);
    } finally {
      setProviderSaving(false);
    }
  }, [provider]);

  const fetchKeys = useCallback(async () => {
    setLoading(true);
    setError('');
    try {
      const response = await fetch('/api/admin/keys', { cache: 'no-store' });
      const payload = await parseResponse(response);
      setKeys(payload.data || []);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchKeys();
    fetchProvider();
  }, [fetchKeys, fetchProvider]);

  const createKey = useCallback(async () => {
    if (!form.name.trim() || !form.apiKey.trim()) {
      setError('Vui lòng nhập đầy đủ Name và API Key.');
      return;
    }

    setSubmitting(true);
    setError('');
    setNotice('');

    try {
      const response = await fetch('/api/admin/keys', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name: form.name, apiKey: form.apiKey }),
      });
      await parseResponse(response);
      setForm({ name: '', apiKey: '' });
      setNotice('Đã thêm API key.');
      await fetchKeys();
    } catch (err) {
      setError(err.message);
    } finally {
      setSubmitting(false);
    }
  }, [fetchKeys, form.apiKey, form.name]);

  const updateStatus = useCallback(async (id, status) => {
    setError('');
    setNotice('');
    try {
      const response = await fetch(`/api/admin/keys/${id}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ status }),
      });
      await parseResponse(response);
      setNotice(`Đã cập nhật trạng thái thành ${status}.`);
      await fetchKeys();
    } catch (err) {
      setError(err.message);
    }
  }, [fetchKeys]);

  const deleteKey = useCallback(async (id) => {
    setError('');
    setNotice('');
    try {
      const response = await fetch(`/api/admin/keys/${id}`, {
        method: 'DELETE',
      });
      await parseResponse(response);
      setNotice('Đã xóa key.');
      await fetchKeys();
    } catch (err) {
      setError(err.message);
    }
  }, [fetchKeys]);

  const resetCounters = useCallback(async () => {
    setError('');
    setNotice('');
    try {
      const response = await fetch('/api/admin/keys/reset', { method: 'POST' });
      await parseResponse(response);
      setNotice('Đã reset daily counters (exhausted -> active).');
      await fetchKeys();
    } catch (err) {
      setError(err.message);
    }
  }, [fetchKeys]);

  return (
    <div className="h-full flex flex-col px-4 py-4 safe-top">
      <div className="flex items-center justify-between pb-4">
        <div className="flex items-center gap-3">
          <NavButton />
          <h1 className="text-[18px] font-extrabold tracking-neo uppercase">
            ADMIN KEYS
          </h1>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={fetchKeys}
            className="rounded-xl neo-border bg-white p-2 neo-press"
            title="Refresh"
          >
            <RefreshCcw size={14} />
          </button>
        </div>
      </div>

      <div className="rounded-2xl neo-border bg-white p-4 neo-shadow-md mb-4">
        <div className="flex items-center justify-between pb-3">
          <div className="flex items-center gap-2">
            <Cpu size={14} />
            <span className="text-[12px] font-bold tracking-neo-wide uppercase">
              Extract Engine
            </span>
          </div>
          <button
            onClick={fetchProvider}
            className="rounded-lg neo-border bg-white p-1.5 neo-press"
            title="Refresh provider"
          >
            <RefreshCcw size={12} />
          </button>
        </div>
        <p className="text-[11px] opacity-60 pb-3">
          Chọn engine xử lý extract job. Thay đổi chỉ áp dụng cho job được worker claim sau khi lưu — job đang chạy giữ engine cũ.
        </p>
        {providerLoading ? (
          <div className="text-[11px] font-bold opacity-50 py-2">LOADING ENGINE...</div>
        ) : (
          <div className="flex flex-col gap-2">
            <select
              value={provider}
              onChange={(e) => setProvider(e.target.value)}
              className="rounded-xl neo-border px-3 py-2 text-[12px] font-bold"
            >
              {PROVIDER_OPTIONS.map((option) => (
                <option key={option.id} value={option.id}>
                  {option.label}
                </option>
              ))}
            </select>
            <ActionButton
              onClick={saveProvider}
              bg="bg-accent-yellow"
              disabled={providerSaving}
            >
              {providerSaving ? 'SAVING...' : 'SAVE EXTRACT ENGINE'}
            </ActionButton>
          </div>
        )}
        {providerError && (
          <div className="rounded-xl neo-border bg-accent-pink px-3 py-2 text-[11px] font-bold mt-3">
            {providerError}
          </div>
        )}
        {providerNotice && (
          <div className="rounded-xl neo-border bg-accent-green px-3 py-2 text-[11px] font-bold mt-3">
            {providerNotice}
          </div>
        )}
      </div>

      <div className="rounded-2xl neo-border bg-white p-4 neo-shadow-md mb-4">
        <div className="flex items-center justify-between pb-3">
          <div className="flex items-center gap-2">
            <Shield size={14} />
            <span className="text-[12px] font-bold tracking-neo-wide uppercase">
              Server Status
            </span>
          </div>
          <span className="text-[11px] font-bold">
            Active: {activeCount}/{keys.length}
          </span>
        </div>
        <p className="text-[11px] opacity-60">
          Dev-only UI: không cần đăng nhập ở client. Secret được giữ ở Next.js API proxy.
        </p>
      </div>

      <div className="rounded-2xl neo-border bg-white p-4 neo-shadow-md mb-4">
        <div className="text-[12px] font-bold tracking-neo-wide uppercase pb-3">
          Add Key
        </div>
        <div className="flex flex-col gap-2">
          <input
            value={form.name}
            onChange={(e) => setForm((prev) => ({ ...prev, name: e.target.value }))}
            placeholder="Key name"
            className="w-full px-3 py-2 rounded-xl neo-border text-[12px] font-medium focus:outline-none"
          />
          <textarea
            value={form.apiKey}
            onChange={(e) => setForm((prev) => ({ ...prev, apiKey: e.target.value }))}
            placeholder="AIza..."
            rows={3}
            className="w-full px-3 py-2 rounded-xl neo-border text-[12px] font-mono focus:outline-none resize-none"
          />
          <ActionButton
            onClick={createKey}
            icon={Plus}
            bg="bg-accent-yellow"
            disabled={submitting}
          >
            {submitting ? 'ADDING...' : 'ADD API KEY'}
          </ActionButton>
        </div>
      </div>

      <div className="flex items-center justify-end pb-2">
        <button
          onClick={resetCounters}
          className="text-[11px] font-bold tracking-neo rounded-xl neo-border bg-accent-green px-3 py-1.5 neo-press"
        >
          RESET DAILY COUNTERS
        </button>
      </div>

      {error && (
        <div className="rounded-xl neo-border bg-accent-pink px-3 py-2 text-[11px] font-bold mb-3">
          {error}
        </div>
      )}
      {notice && (
        <div className="rounded-xl neo-border bg-accent-green px-3 py-2 text-[11px] font-bold mb-3">
          {notice}
        </div>
      )}

      <div className="flex-1 overflow-auto scrollbar-hide pb-8">
        {loading ? (
          <div className="text-[11px] font-bold opacity-50 py-8 text-center">LOADING...</div>
        ) : keys.length === 0 ? (
          <div className="text-[11px] font-bold opacity-50 py-8 text-center">
            NO API KEYS YET
          </div>
        ) : (
          <div className="flex flex-col gap-3">
            {keys.map((key) => (
              <div key={key.id} className="rounded-2xl neo-border bg-white p-3 neo-shadow-sm">
                <div className="flex items-center justify-between gap-2">
                  <div>
                    <div className="text-[13px] font-extrabold tracking-neo">{key.name}</div>
                    <div className="text-[10px] opacity-60">{key.id}</div>
                  </div>
                  <button
                    onClick={() => deleteKey(key.id)}
                    className="rounded-lg neo-border bg-accent-pink p-2 neo-press"
                    title="Delete key"
                  >
                    <Trash2 size={12} />
                  </button>
                </div>
                <div className="flex items-center justify-between pt-3">
                  <div className="text-[10px] font-bold opacity-70">
                    Requests Today: {key.requestsToday}
                  </div>
                  <select
                    value={key.status}
                    onChange={(e) => updateStatus(key.id, e.target.value)}
                    className="rounded-lg neo-border px-2 py-1 text-[10px] font-bold"
                  >
                    {STATUS_OPTIONS.map((status) => (
                      <option key={status} value={status}>
                        {status.toUpperCase()}
                      </option>
                    ))}
                  </select>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
