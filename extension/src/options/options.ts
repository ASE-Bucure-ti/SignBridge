import browser from 'webextension-polyfill';
import { STORAGE_ALLOWED_ORIGINS } from '../shared/constants';

// ---------------------------------------------------------------------------
// DOM Elements
// ---------------------------------------------------------------------------
const form = document.getElementById('add-origin-form') as HTMLFormElement;
const input = document.getElementById('new-origin') as HTMLInputElement;
const list = document.getElementById('origin-list') as HTMLUListElement;
const toast = document.getElementById('toast') as HTMLDivElement;
const versionSpan = document.getElementById('ext-version') as HTMLSpanElement;

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------
let allowedOrigins: string[] = [];

// ---------------------------------------------------------------------------
// Functions
// ---------------------------------------------------------------------------

async function loadSettings() {
  try {
    const result = await browser.storage.sync.get(STORAGE_ALLOWED_ORIGINS);
    allowedOrigins = (result[STORAGE_ALLOWED_ORIGINS] as string[] | undefined) || [];
    renderList();
  } catch (error) {
    console.error('Failed to load settings:', error);
  }
}

async function saveSettings() {
  try {
    await browser.storage.sync.set({
      [STORAGE_ALLOWED_ORIGINS]: allowedOrigins,
    });
    showToast();
  } catch (error) {
    console.error('Failed to save settings:', error);
    alert('Failed to save settings. See console for details.');
  }
}

function renderList() {
  list.innerHTML = '';
  
  if (allowedOrigins.length === 0) {
    const emptyState = document.createElement('li');
    emptyState.className = 'origin-item';
    emptyState.style.justifyContent = 'center';
    emptyState.style.color = '#605e5c';
    emptyState.style.fontStyle = 'italic';
    emptyState.textContent = 'No allowed origins configured.';
    list.appendChild(emptyState);
    return;
  }

  allowedOrigins.forEach((origin, index) => {
    const li = document.createElement('li');
    li.className = 'origin-item';

    const span = document.createElement('span');
    span.className = 'origin-url';
    span.textContent = origin;

    const btn = document.createElement('button');
    btn.className = 'btn danger';
    btn.textContent = 'Remove';
    btn.setAttribute('aria-label', `Remove ${origin}`);
    btn.onclick = () => removeOrigin(index);

    li.appendChild(span);
    li.appendChild(btn);
    list.appendChild(li);
  });
}

async function addOrigin(url: string) {
  try {
    const origin = new URL(url).origin;
    
    if (allowedOrigins.includes(origin)) {
      alert('This origin is already in the allowlist.');
      return;
    }

    allowedOrigins.push(origin);
    await saveSettings();
    renderList();
    form.reset();
  } catch (e) {
    alert('Invalid URL. Please enter a full URL starting with http:// or https://');
  }
}

async function removeOrigin(index: number) {
  allowedOrigins.splice(index, 1);
  await saveSettings();
  renderList();
}

function showToast() {
  toast.classList.remove('hidden');
  setTimeout(() => {
    toast.classList.add('hidden');
  }, 2000);
}

function setVersion() {
  const manifest = browser.runtime.getManifest();
  versionSpan.textContent = manifest.version;
}

// ---------------------------------------------------------------------------
// Event Listeners
// ---------------------------------------------------------------------------

document.addEventListener('DOMContentLoaded', () => {
  loadSettings();
  setVersion();
});

form.addEventListener('submit', (e) => {
  e.preventDefault();
  const val = input.value.trim();
  if (val) {
    addOrigin(val);
  }
});
