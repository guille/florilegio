(async () => {
  // ── Config ──────────────────────────────────────────────────────────────────

  const { apiUrl, apiToken } = await browser.storage.local.get(["apiUrl", "apiToken"]);

  if (!apiUrl || !apiToken) {
    show("state-no-config");
    return;
  }

  // ── Grab current tab info ───────────────────────────────────────────────────

  const [tab] = await browser.tabs.query({ active: true, currentWindow: true });
  if (!tab?.url) {
    showError("No active tab");
    return;
  }

  // ── Save bookmark immediately ───────────────────────────────────────────────

  let bookmarkId;

  try {
    const res = await apiFetch("POST", "/bookmarks", {
      url: tab.url,
      title: tab.title || null,
    });

    if (res.status === 409) {
      show("state-duplicate");
      autoClose(2000);
      return;
    }

    if (!res.ok) {
      const body = await res.json().catch(() => ({}));
      showError(body.error || `HTTP ${res.status}`);
      return;
    }

    const bookmark = await res.json();
    bookmarkId = bookmark.id;

    // Populate editable fields and store originals for dirty-checking
    const titleEl = document.getElementById("title");
    const tagsEl = document.getElementById("tags");
    titleEl.value = bookmark.title || "";
    titleEl.dataset.original = bookmark.title || "";
    tagsEl.value = bookmark.tags || "";
    tagsEl.dataset.original = bookmark.tags || "";
    show("state-saved");
  } catch (err) {
    showError(err.message || "Network error");
    return;
  }

  // ── Update on button click ────────────────────────────────────────────────

  document.getElementById("btn-update").addEventListener("click", async (e) => {
    const btn = e.target;
    btn.disabled = true;
    btn.textContent = "Updating...";

    const title = document.getElementById("title").value.trim();
    const tags = document.getElementById("tags").value.trim();

    // Only send fields that the user actually changed to avoid clearing data.
    const body = {};
    const originalTitle = document.getElementById("title").dataset.original;
    const originalTags = document.getElementById("tags").dataset.original;
    if (title !== originalTitle) body.title = title || null;
    if (tags !== originalTags) body.tags = tags || null;

    if (Object.keys(body).length === 0) {
      show("state-updated");
      autoClose(1500);
      return;
    }

    try {
      const res = await apiFetch("PATCH", `/bookmarks/${bookmarkId}`, body);

      if (!res.ok) {
        const body = await res.json().catch(() => ({}));
        showError(body.error || `HTTP ${res.status}`);
        return;
      }

      show("state-updated");
      autoClose(1500);
    } catch (err) {
      showError(err.message || "Network error");
    }
  });

  // ── Helpers ─────────────────────────────────────────────────────────────────

  function apiFetch(method, path, body) {
    return fetch(apiUrl.replace(/\/+$/, "") + path, {
      method,
      headers: {
        Authorization: `Bearer ${apiToken}`,
        "Content-Type": "application/json",
      },
      body: body ? JSON.stringify(body) : undefined,
    });
  }

  function show(id) {
    document.querySelectorAll(".state").forEach((el) => el.classList.add("hidden"));
    document.getElementById(id).classList.remove("hidden");
  }

  function showError(msg) {
    document.getElementById("error-msg").textContent = msg;
    show("state-error");
  }

  function autoClose(ms) {
    setTimeout(() => window.close(), ms);
  }
})();
