(async () => {
  const urlInput = document.getElementById("apiUrl");
  const tokenInput = document.getElementById("apiToken");
  const btn = document.getElementById("btn-save");
  const status = document.getElementById("status");

  // Load saved values
  const { apiUrl, apiToken } = await browser.storage.local.get(["apiUrl", "apiToken"]);
  let savedUrl = apiUrl || "";
  let savedToken = apiToken || "";
  urlInput.value = savedUrl;
  tokenInput.value = savedToken;

  function updateDirty() {
    const dirty = urlInput.value.trim() !== savedUrl || tokenInput.value.trim() !== savedToken;
    btn.disabled = !dirty;
  }

  urlInput.addEventListener("input", updateDirty);
  tokenInput.addEventListener("input", updateDirty);

  let statusTimer;
  function showStatus(text, className) {
    clearTimeout(statusTimer);
    status.textContent = text;
    status.className = "status visible " + className;
    statusTimer = setTimeout(() => {
      status.classList.remove("visible");
    }, 2500);
  }

  btn.addEventListener("click", async () => {
    const url = urlInput.value.trim();
    const token = tokenInput.value.trim();

    if (!url || !token) {
      showStatus("Both fields are required", "error");
      return;
    }

    btn.disabled = true;
    btn.textContent = "Saving...";

    try {
      await browser.storage.local.set({ apiUrl: url, apiToken: token });
      savedUrl = url;
      savedToken = token;
      showStatus("Saved", "saved");
    } catch (e) {
      showStatus("Failed to save", "error");
      updateDirty();
    } finally {
      btn.textContent = "Save";
    }
  });
})();
