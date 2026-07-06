(function () {
  function escapeHtml(str) {
    return String(str)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#039;");
  }

  window.showAlert = function (message, opts) {
    opts = opts || {};
    // Remove alerta anterior se existir
    const prev = document.querySelector(".alerts-overlay");
    if (prev) prev.remove();

    const overlay = document.createElement("div");
    overlay.className = "alerts-overlay";

    const safe = escapeHtml(message).replace(/\n/g, "<br>");
    overlay.innerHTML = `
      <div class="alerts">
        <div class="alert" role="dialog" aria-modal="true">
          <div class="alert-message">${safe}</div>
          <div class="alert-actions">
            <button class="alert-ok">OK</button>
          </div>
        </div>
      </div>
    `;

    document.body.appendChild(overlay);
    const ok = overlay.querySelector(".alert-ok");
    ok.focus();

    function closeAndCallback() {
      try {
        overlay.remove();
      } catch (e) {}
      if (typeof opts.onOk === "function") {
        try {
          opts.onOk();
        } catch (e) {
          console.error(e);
        }
      }
    }

    ok.addEventListener("click", closeAndCallback);
    overlay.addEventListener("click", (e) => {
      if (e.target === overlay && opts.dismissOnBackdrop !== false)
        closeAndCallback();
    });
  };
})();
