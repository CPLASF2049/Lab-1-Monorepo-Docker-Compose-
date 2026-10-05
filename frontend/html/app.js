'use strict';

// The page is served by the frontend container, so it always talks to the same
// origin and nginx forwards /api/* to the backend service.
const API_BASE = '/api';

const valueEl = document.getElementById('value');
const statusEl = document.getElementById('status');
const incrementBtn = document.getElementById('increment');
const decrementBtn = document.getElementById('decrement');

function setBusy(busy) {
  incrementBtn.disabled = busy;
  decrementBtn.disabled = busy;
}

function setStatus(message, isError) {
  statusEl.textContent = message || '';
  statusEl.classList.toggle('error', Boolean(isError));
}

async function callApi(path, options) {
  const response = await fetch(`${API_BASE}${path}`, {
    headers: { Accept: 'application/json' },
    ...options,
  });

  let payload = null;
  try {
    payload = await response.json();
  } catch (err) {
    payload = null;
  }

  if (!response.ok) {
    const detail = payload && (payload.error || payload.message);
    throw new Error(detail || `HTTP ${response.status}`);
  }
  if (!payload || typeof payload.value !== 'number') {
    throw new Error('响应格式不正确');
  }
  return payload.value;
}

function render(value) {
  valueEl.textContent = String(value);
}

// Reading the counter on page load / refresh never changes the stored value.
async function load() {
  setBusy(true);
  setStatus('正在读取数据库中的计数值…', false);
  try {
    render(await callApi('/counter'));
    setStatus('已从数据库读取', false);
  } catch (err) {
    valueEl.textContent = '—';
    setStatus(`读取失败：${err.message}`, true);
  } finally {
    setBusy(false);
  }
}

// The backend only answers after the database write has been committed, so the
// value shown here is the value actually stored in PostgreSQL.
async function change(action) {
  setBusy(true);
  setStatus('正在写入数据库…', false);
  try {
    render(await callApi(`/counter/${action}`, { method: 'POST' }));
    setStatus('已写入数据库', false);
  } catch (err) {
    setStatus(`操作失败：${err.message}`, true);
  } finally {
    setBusy(false);
  }
}

incrementBtn.addEventListener('click', () => change('increment'));
decrementBtn.addEventListener('click', () => change('decrement'));

load();
