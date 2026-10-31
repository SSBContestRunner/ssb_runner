/* Shared prototype behaviour: icons, theme, overlays, tabs, timer, shortcuts. */

const ICONS = {
  settings:
    "M19.14 12.94c.04-.3.06-.61.06-.94s-.02-.64-.07-.94l2.03-1.58c.18-.14.23-.41.12-.61l-1.92-3.32c-.12-.22-.37-.29-.59-.22l-2.39.96c-.5-.38-1.03-.7-1.62-.94l-.36-2.54c-.04-.24-.24-.41-.48-.41h-3.84c-.24 0-.43.17-.47.41l-.36 2.54c-.59.24-1.13.57-1.62.94l-2.39-.96c-.22-.08-.47 0-.59.22L2.74 8.87c-.12.21-.08.47.12.61l2.03 1.58c-.05.3-.09.63-.09.94s.02.64.07.94l-2.03 1.58c-.18.14-.23.41-.12.61l1.92 3.32c.12.22.37.29.59.22l2.39-.96c.5.38 1.03.7 1.62.94l.36 2.54c.05.24.24.41.48.41h3.84c.24 0 .44-.17.47-.41l.36-2.54c.59-.24 1.13-.56 1.62-.94l2.39.96c.22.08.47 0 .59-.22l1.92-3.32c.12-.22.07-.47-.12-.61l-2.01-1.58zM12 15.6c-1.98 0-3.6-1.62-3.6-3.6s1.62-3.6 3.6-3.6 3.6 1.62 3.6 3.6-1.62 3.6-3.6 3.6z",
  keyboard:
    "M20 5H4c-1.1 0-1.99.9-1.99 2L2 17c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V7c0-1.1-.9-2-2-2zm-9 3h2v2h-2V8zm0 3h2v2h-2v-2zM8 8h2v2H8V8zm0 3h2v2H8v-2zm-1 2H5v-2h2v2zm0-3H5V8h2v2zm9 7H8v-2h8v2zm0-4h-2v-2h2v2zm0-3h-2V8h2v2zm3 3h-2v-2h2v2zm0-3h-2V8h2v2z",
  dark_mode:
    "M12 3c-4.97 0-9 4.03-9 9s4.03 9 9 9 9-4.03 9-9c0-.46-.04-.92-.1-1.36-.98 1.37-2.58 2.26-4.4 2.26-2.98 0-5.4-2.42-5.4-5.4 0-1.81.89-3.42 2.26-4.4-.44-.06-.9-.1-1.36-.1z",
  light_mode:
    "M12 7c-2.76 0-5 2.24-5 5s2.24 5 5 5 5-2.24 5-5-2.24-5-5-5zM2 13h2c.55 0 1-.45 1-1s-.45-1-1-1H2c-.55 0-1 .45-1 1s.45 1 1 1zm18 0h2c.55 0 1-.45 1-1s-.45-1-1-1h-2c-.55 0-1 .45-1 1s.45 1 1 1zM11 2v2c0 .55.45 1 1 1s1-.45 1-1V2c0-.55-.45-1-1-1s-1 .45-1 1zm0 18v2c0 .55.45 1 1 1s1-.45 1-1v-2c0-.55-.45-1-1-1s-1 .45-1 1zM5.99 4.58c-.39-.39-1.03-.39-1.41 0-.39.39-.39 1.03 0 1.41l1.06 1.06c.39.39 1.03.39 1.41 0s.39-1.03 0-1.41L5.99 4.58zm12.37 12.37c-.39-.39-1.03-.39-1.41 0-.39.39-.39 1.03 0 1.41l1.06 1.06c.39.39 1.03.39 1.41 0 .39-.39.39-1.03 0-1.41l-1.06-1.06zm1.06-10.96c.39-.39.39-1.03 0-1.41-.39-.39-1.03-.39-1.41 0l-1.06 1.06c-.39.39-.39 1.03 0 1.41s1.03.39 1.41 0l1.06-1.06zM7.05 18.36c.39-.39.39-1.03 0-1.41-.39-.39-1.03-.39-1.41 0l-1.06 1.06c-.39.39-.39 1.03 0 1.41s1.03.39 1.41 0l1.06-1.06z",
  radio:
    "M3.24 6.15C2.51 6.43 2 7.17 2 8v12c0 1.1.89 2 2 2h16c1.11 0 2-.9 2-2V8c0-1.11-.89-2-2-2H8.3l8.26-3.34L15.88 1 3.24 6.15zM7 20c-1.66 0-3-1.34-3-3s1.34-3 3-3 3 1.34 3 3-1.34 3-3 3zm13-8h-2v-2h-2v2H4V8h16v4z",
  play_arrow: "M8 5v14l11-7z",
  pause: "M6 19h4V5H6v14zm8-14v14h4V5h-4z",
  stop: "M6 6h12v12H6z",
  expand_more: "M16.59 8.59 12 13.17 7.41 8.59 6 10l6 6 6-6z",
  close:
    "M19 6.41 17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z",
  info: "M11 7h2v2h-2zm0 4h2v6h-2zm1-9C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 18c-4.41 0-8-3.59-8-8s3.59-8 8-8 8 3.59 8 8-3.59 8-8 8z",
  tune: "M3 17v2h6v-2H3zM3 5v2h10V5H3zm10 16v-2h8v-2h-8v-2h-2v6h2zM7 9v2H3v2h4v2h2V9H7zm14 4v-2H11v2h10zm-6-4h2V7h4V5h-4V3h-2v6z",
  timer:
    "M15 1H9v2h6V1zm-4 13h2V8h-2v6zm8.03-6.61 1.42-1.42c-.43-.51-.9-.99-1.41-1.41l-1.42 1.42C16.07 4.74 14.12 4 12 4c-4.97 0-9 4.03-9 9s4.02 9 9 9 9-4.03 9-9c0-2.12-.74-4.07-1.97-5.61zM12 20c-3.87 0-7-3.13-7-7s3.13-7 7-7 7 3.13 7 7-3.13 7-7 7z",
  trophy:
    "M19 5h-2V3H7v2H5c-1.1 0-2 .9-2 2v1c0 2.55 1.92 4.63 4.39 4.94.63 1.5 1.98 2.63 3.61 2.96V19H7v2h10v-2h-4v-3.1c1.63-.33 2.98-1.46 3.61-2.96C19.08 12.63 21 10.55 21 8V7c0-1.1-.9-2-2-2zM7 10.82C5.84 10.4 5 9.3 5 8V7h2v3.82zM19 8c0 1.3-.84 2.4-2 2.82V7h2v1z",
  speed:
    "M20.38 8.57-1.23 1.85a8 8 0 0 1-.22 7.58H5.07A8 8 0 0 1 15.58 6.85l1.85-1.23A10 10 0 0 0 3.35 19a2 2 0 0 0 1.72 1h13.85a2 2 0 0 0 1.74-1 10 10 0 0 0-.28-10.43zm-9.79 6.84a2 2 0 0 0 2.83 0l5.66-8.49-8.49 5.66a2 2 0 0 0 0 2.83z",
  table_chart:
    "M10 10.02h5V21h-5zM17 21h3c1.1 0 2-.9 2-2v-9h-5v11zm3-18H5c-1.1 0-2 .9-2 2v3h19V5c0-1.1-.9-2-2-2zM3 19c0 1.1.9 2 2 2h3V10H3v9z",
  list_alt:
    "M3 5v14h18V5H3zm5 12H5v-3h3v3zm0-5H5V9h3v3zm0-5H5V5h3v2zm11 10h-9v-3h9v3zm0-5h-9V9h9v3zm0-5h-9V5h9v2z",
  chevron_right: "M10 6 8.59 7.41 13.17 12l-4.58 4.59L10 18l6-6z",
  content_copy:
    "M16 1H4c-1.1 0-2 .9-2 2v14h2V3h12V1zm3 4H8c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h11c1.1 0 2-.9 2-2V7c0-1.1-.9-2-2-2zm0 16H8V7h11v14z",
  download: "M19 9h-4V3H9v6H5l7 7 7-7zM5 18v2h14v-2H5z",
  search:
    "M15.5 14h-.79l-.28-.27A6.471 6.471 0 0 0 16 9.5 6.5 6.5 0 1 0 9.5 16c1.61 0 3.09-.59 4.23-1.57l.27.28v.79l5 4.99L20.49 19l-4.99-5zm-6 0C7.01 14 5 11.99 5 9.5S7.01 5 9.5 5 14 7.01 14 9.5 11.99 14 9.5 14z",
  history:
    "M13 3c-4.97 0-9 4.03-9 9H1l3.89 3.89.07.14L9 12H6c0-3.87 3.13-7 7-7s7 3.13 7 7-3.13 7-7 7c-1.93 0-3.68-.79-4.94-2.06l-1.42 1.42C8.27 19.99 10.51 21 13 21c4.97 0 9-4.03 9-9s-4.03-9-9-9zm-1 5v5l4.28 2.54.72-1.21-3.5-2.08V8H12z",
  casino:
    "M19 3H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zM7.5 18c-.83 0-1.5-.67-1.5-1.5S6.67 15 7.5 15s1.5.67 1.5 1.5S8.33 18 7.5 18zm0-9C6.67 9 6 8.33 6 7.5S6.67 6 7.5 6 9 6.67 9 7.5 8.33 9 7.5 9zm4.5 4.5c-.83 0-1.5-.67-1.5-1.5s.67-1.5 1.5-1.5 1.5.67 1.5 1.5-.67 1.5-1.5 1.5zm4.5 4.5c-.83 0-1.5-.67-1.5-1.5s.67-1.5 1.5-1.5 1.5.67 1.5 1.5-.67 1.5-1.5 1.5zm0-9c-.83 0-1.5-.67-1.5-1.5S15.67 6 16.5 6s1.5.67 1.5 1.5S17.33 9 16.5 9z",
  graphic_eq:
    "M7 18h2V6H7v12zm4 4h2V2h-2v20zM3 14h2v-4H3v4zm12 4h2V6h-2v12zm4-8v4h2v-4h-2z",
  person:
    "M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 3c1.66 0 3 1.34 3 3s-1.34 3-3 3-3-1.34-3-3 1.34-3 3-3zm0 14.2c-2.5 0-4.71-1.28-6-3.22.03-1.99 4-3.08 6-3.08 1.99 0 5.97 1.09 6 3.08-1.29 1.94-3.5 3.22-6 3.22z",
  language:
    "M11.99 2C6.47 2 2 6.48 2 12s4.47 10 9.99 10C17.52 22 22 17.52 22 12S17.52 2 11.99 2zm6.93 6h-2.95c-.32-1.25-.78-2.45-1.38-3.56 1.84.63 3.37 1.91 4.33 3.56zM12 4.04c.83 1.2 1.48 2.53 1.91 3.96h-3.82c.43-1.43 1.08-2.76 1.91-3.96zM4.26 14C4.1 13.36 4 12.69 4 12s.1-1.36.26-2h3.38c-.08.66-.14 1.32-.14 2 0 .68.06 1.34.14 2H4.26zm.82 2h2.95c.32 1.25.78 2.45 1.38 3.56-1.84-.63-3.37-1.9-4.33-3.56zm2.95-8H5.08c.96-1.66 2.49-2.93 4.33-3.56C8.81 5.55 8.35 6.75 8.03 8zM12 19.96c-.83-1.2-1.48-2.53-1.91-3.96h3.82c-.43 1.43-1.08 2.76-1.91 3.96zM14.34 14H9.66c-.09-.66-.16-1.32-.16-2 0-.68.07-1.35.16-2h4.68c.09.65.16 1.32.16 2 0 .68-.07 1.34-.16 2zm.25 5.56c.6-1.11 1.06-2.31 1.38-3.56h2.95c-.96 1.65-2.49 2.93-4.33 3.56zM16.36 14c.08-.66.14-1.32.14-2 0-.68-.06-1.34-.14-2h3.38c.16.64.26 1.31.26 2s-.1 1.36-.26 2h-3.38z",
  more_horiz:
    "M6 10c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2zm12 0c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2zm-6 0c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2z",
  send: "M2.01 21 23 12 2.01 3 2 10l15 2-15 2z",
  check_circle:
    "M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z",
  error:
    "M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-2h2v2zm0-4h-2V7h2v6z",
  flag: "M14.4 6 14 4H5v17h2v-7h5.6l.4 2h7V6z",
  help: "M11 18h2v-2h-2v2zm1-16C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 18c-4.41 0-8-3.59-8-8s3.59-8 8-8 8 3.59 8 8-3.59 8-8 8zm0-14c-2.21 0-4 1.79-4 4h2c0-1.1.9-2 2-2s2 .9 2 2c0 2-3 1.75-3 5h2c0-2.25 3-2.5 3-5 0-2.21-1.79-4-4-4z",
  mic: "M12 14c1.66 0 3-1.34 3-3V5c0-1.66-1.34-3-3-3S9 3.34 9 5v6c0 1.66 1.34 3 3 3zm5.91-3c-.49 0-.9.36-.98.85C16.52 14.2 14.47 16 12 16s-4.52-1.8-4.93-4.15c-.08-.49-.49-.85-.98-.85-.61 0-1.09.54-1 1.14.49 3 2.89 5.35 5.91 5.78V20c0 .55.45 1 1 1s1-.45 1-1v-2.08c3.02-.43 5.42-2.78 5.91-5.78.1-.6-.39-1.14-1-1.14z",
  volume_up:
    "M3 9v6h4l5 5V4L7 9H3zm13.5 3c0-1.77-1.02-3.29-2.5-4.03v8.05c1.48-.73 2.5-2.25 2.5-4.02zM14 3.23v2.06c2.89.86 5 3.54 5 6.71s-2.11 5.85-5 6.71v2.06c4.01-.91 7-4.49 7-8.77s-2.99-7.86-7-8.77z",
  schedule:
    "M11.99 2C6.47 2 2 6.48 2 12s4.47 10 9.99 10C17.52 22 22 17.52 22 12S17.52 2 11.99 2zM12 20c-4.42 0-8-3.58-8-8s3.58-8 8-8 8 3.58 8 8-3.58 8-8 8zm.5-13H11v6l5.25 3.15.75-1.23-4.5-2.67z",
  arrow_back: "M20 11H7.83l5.59-5.59L12 4l-8 8 8 8 1.41-1.41L7.83 13H20v-2z",
  menu: "M3 18h18v-2H3v2zm0-5h18v-2H3v2zm0-7v2h18V6H3z",
  dashboard: "M3 13h8V3H3v10zm0 8h8v-6H3v6zm10 0h8V11h-8v10zm0-18v6h8V3h-8z",
  bar_chart: "M5 9.2h3V19H5zM10.6 5h2.8v14h-2.8zm5.6 8H19v6h-2.8z",
  school: "M5 13.18v4L12 21l7-3.82v-4L12 17l-7-3.82zM12 3 1 9l11 6 9-4.91V17h2V9L12 3z",
  description:
    "M14 2H6c-1.1 0-1.99.9-1.99 2L4 20c0 1.1.89 2 1.99 2H18c1.1 0 2-.9 2-2V8l-6-6zm2 16H8v-2h8v2zm0-4H8v-2h8v2zm-3-5V3.5L18.5 9H13z",
  north_east: "M9 5v2h6.59L4 18.59 5.41 20 17 8.41V15h2V5z",
  bolt: "M11 21h-1l1-7H7.5c-.58 0-.57-.32-.38-.66.19-.34.05-.08.07-.12C8.48 10.94 10.42 7.54 13 3h1l-1 7h3.5c.49 0 .56.33.47.51l-.07.15C12.96 17.55 11 21 11 21z"
};

const KEY_ACTIONS = {
  F1: "CQ",
  F2: "EXCH",
  F3: "TU",
  F4: "<my>",
  F5: "<his>",
  F6: "B4",
  F7: "AGN",
  F8: "NIL",
  F9: "Spare",
  F10: "Spare",
  F11: "Spare",
  F12: "Wipe"
};

function hydrateIcons(root = document) {
  root.querySelectorAll("[data-icon]").forEach((el) => {
    const name = el.getAttribute("data-icon");
    const path = ICONS[name];
    if (!path) return;
    el.innerHTML = `<svg viewBox="0 0 24 24" aria-hidden="true" focusable="false"><path fill="currentColor" d="${path}"/></svg>`;
  });
}

function initTheme() {
  let stored = null;
  try {
    stored = localStorage.getItem("ssb-proto-theme");
  } catch (_) {
    /* file:// restrictions can deny storage */
  }
  const wanted = new URLSearchParams(location.search).get("theme");
  const theme = wanted === "dark" ? "dark" : wanted === "light" ? "light" : stored === "dark" ? "dark" : "light";
  document.documentElement.dataset.theme = theme;
  syncThemeButtons();
  hydrateIcons();

  document.addEventListener("click", (event) => {
    const button = event.target.closest("[data-theme-toggle]");
    if (!button) return;
    const next =
      document.documentElement.dataset.theme === "dark" ? "light" : "dark";
    document.documentElement.dataset.theme = next;
    try {
      localStorage.setItem("ssb-proto-theme", next);
    } catch (_) {
      /* ignore */
    }
    syncThemeButtons();
    hydrateIcons();
  });
}

function syncThemeButtons() {
  const dark = document.documentElement.dataset.theme === "dark";
  document.querySelectorAll("[data-theme-toggle]").forEach((button) => {
    const icon = button.querySelector("[data-icon]");
    if (icon) icon.setAttribute("data-icon", dark ? "light_mode" : "dark_mode");
    button.setAttribute("aria-label", dark ? "切换到浅色主题" : "切换到深色主题");
    button.setAttribute("title", dark ? "浅色主题" : "深色主题");
  });
}

/* ---------- Tabs ---------- */

function initTabs() {
  document.querySelectorAll("[data-tabs]").forEach((tabs) => {
    const scope = tabs.closest("[data-tab-scope]") || document;
    const buttons = [...tabs.querySelectorAll("[data-tab]")];
    const panels = [...scope.querySelectorAll("[data-tab-panel]")];
    if (!buttons.length) return;

    const activate = (button, focus = false) => {
      const id = button.dataset.tab;
      buttons.forEach((b) => {
        const selected = b === button;
        b.setAttribute("aria-selected", String(selected));
        b.tabIndex = selected ? 0 : -1;
      });
      panels.forEach((panel) => {
        panel.classList.toggle("hidden", panel.dataset.tabPanel !== id);
      });
      if (focus) button.focus();
    };

    buttons.forEach((button, index) => {
      button.addEventListener("click", () => activate(button));
      button.addEventListener("keydown", (event) => {
        if (event.key !== "ArrowRight" && event.key !== "ArrowLeft") return;
        event.preventDefault();
        const dir = event.key === "ArrowRight" ? 1 : -1;
        const next = buttons[(index + dir + buttons.length) % buttons.length];
        activate(next, true);
      });
    });

    const initial =
      buttons.find((b) => b.getAttribute("aria-selected") === "true") ||
      buttons[0];
    activate(initial);
  });
}

/* ---------- Overlays ---------- */

let lastFocused = null;

function focusables(root) {
  return [
    ...root.querySelectorAll(
      'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])'
    )
  ].filter(
    (el) =>
      !el.disabled &&
      el.getAttribute("aria-hidden") !== "true" &&
      el.offsetParent !== null
  );
}

function openOverlay(overlay, trigger) {
  if (!overlay) return;
  document.querySelectorAll(".overlay.is-open").forEach(closeOverlay);
  lastFocused = trigger || document.activeElement;
  overlay.classList.add("is-open");
  overlay.setAttribute("aria-hidden", "false");
  const app = document.querySelector(".app");
  if (app) app.inert = true;
  const target = overlay.querySelector(
    ".side-sheet, .dialog, .fullscreen-dialog, .bottom-sheet"
  );
  window.setTimeout(() => {
    if (target) {
      if (!target.hasAttribute("tabindex")) target.setAttribute("tabindex", "-1");
      target.focus({ preventScroll: true });
    } else {
      overlay.focus?.();
    }
  }, 60);
}

function closeOverlay(overlay) {
  if (!overlay || !overlay.classList.contains("is-open")) return;
  overlay.classList.remove("is-open");
  overlay.setAttribute("aria-hidden", "true");
  const app = document.querySelector(".app");
  if (app) app.inert = false;
  if (lastFocused && document.contains(lastFocused)) {
    lastFocused.focus({ preventScroll: true });
  }
  lastFocused = null;
}

function initOverlays() {
  document.addEventListener("click", (event) => {
    const opener = event.target.closest("[data-open]");
    if (opener) {
      event.preventDefault();
      openOverlay(document.querySelector(opener.dataset.open), opener);
      return;
    }
    const closer = event.target.closest("[data-close]");
    if (closer) {
      event.preventDefault();
      closeOverlay(closer.closest(".overlay"));
    }
  });

  document.addEventListener("keydown", (event) => {
    const overlay = document.querySelector(".overlay.is-open");
    if (!overlay) return;
    if (event.key === "Escape") {
      event.preventDefault();
      closeOverlay(overlay);
      return;
    }
    if (event.key !== "Tab") return;
    const node = overlay.querySelector(
      ".side-sheet, .dialog, .fullscreen-dialog, .bottom-sheet"
    );
    if (!node) return;
    const items = focusables(node);
    if (!items.length) return;
    const first = items[0];
    const last = items[items.length - 1];
    if (event.shiftKey && (document.activeElement === first || document.activeElement === node)) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault();
      first.focus();
    }
  });
}

/* ---------- Timer / run state ---------- */

let elapsed = 754;
let duration = 3600;
let running = true;
let tickHandle = null;

function pad(n) {
  return String(n).padStart(2, "0");
}

function clock(seconds) {
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = seconds % 60;
  return `${pad(h)}:${pad(m)}:${pad(s)}`;
}

function shortClock(seconds) {
  const m = Math.floor(seconds / 60);
  const s = seconds % 60;
  return `${pad(m)}:${pad(s)}`;
}

function renderClock() {
  document.querySelectorAll("[data-timer]").forEach((el) => {
    el.textContent = clock(elapsed);
  });
  document.querySelectorAll("[data-elapsed-short]").forEach((el) => {
    el.textContent = shortClock(elapsed);
  });
  const remaining = Math.max(0, duration - elapsed);
  document.querySelectorAll("[data-remaining]").forEach((el) => {
    el.textContent = shortClock(remaining);
  });
  document.querySelectorAll("[data-progress]").forEach((el) => {
    el.style.width = `${Math.min(100, (elapsed / duration) * 100)}%`;
  });
}

function setRunning(next, announce = true) {
  running = next;
  const stopControl = document.body.dataset.runControl === "stop";
  const idleStatus = stopControl ? "已停止" : "已暂停";
  const runningNote = stopControl ? "计时中 · 随时可停止" : "计时中 · 随时可暂停";
  const idleNote = stopControl ? "已停止 · 数据会保留" : "已暂停 · 数据会保留";
  const app = document.querySelector(".app");
  if (app) app.classList.toggle("is-running", running);
  document.querySelectorAll("[data-run-toggle]").forEach((button) => {
    button.setAttribute("aria-pressed", String(running));
    button.setAttribute("aria-label", running ? "停止训练" : "开始训练");
  });
  document.querySelectorAll("[data-run-status]").forEach((el) => {
    el.classList.toggle("running", running);
    el.classList.toggle("idle", !running);
    const text = el.querySelector("[data-run-status-text]");
    if (text) text.textContent = running ? "进行中" : idleStatus;
    if (!text) el.textContent = running ? "进行中" : idleStatus;
  });
  document.querySelectorAll("[data-run-note]").forEach((el) => {
    el.textContent = running ? runningNote : idleNote;
  });
  if (running) {
    if (!tickHandle) {
      tickHandle = window.setInterval(() => {
        if (!running) return;
        elapsed += 1;
        renderClock();
      }, 1000);
    }
  } else if (tickHandle) {
    window.clearInterval(tickHandle);
    tickHandle = null;
  }
  renderClock();
  syncPhaseHint();
  if (announce) {
    showSnackbar(
      running
        ? "训练已开始，计时继续"
        : stopControl
          ? "训练已停止，数据会保留"
          : "训练已暂停，数据会保留",
      running ? "play_arrow" : "stop"
    );
  }
}

function syncPhaseHint() {
  const line = document.querySelector("[data-phase-hint]");
  if (!line) return;
  const select = document.querySelector("[data-phase-hint-source]");
  const difficulty = select ? select.value : "beginner";
  line.classList.toggle("hidden", !running || difficulty !== "beginner");
  const label = document.querySelector("[data-difficulty-label]");
  if (label && select && select.selectedIndex >= 0) {
    label.textContent = select.options[select.selectedIndex].textContent;
  }
}

function initPhaseHint() {
  const select = document.querySelector("[data-phase-hint-source]");
  if (!select) return;
  const requested = new URLSearchParams(location.search).get("difficulty");
  if (requested && [...select.options].some((option) => option.value === requested)) {
    select.value = requested;
  }
  select.addEventListener("change", syncPhaseHint);
  syncPhaseHint();
}

function initTimer() {
  const timeEl = document.querySelector("[data-timer]");
  if (!timeEl) return;
  const body = document.body;
  const parsedElapsed = Number(body.dataset.elapsed);
  const parsedDuration = Number(body.dataset.duration);
  if (Number.isFinite(parsedElapsed) && parsedElapsed > 0) elapsed = parsedElapsed;
  if (Number.isFinite(parsedDuration) && parsedDuration > 0) duration = parsedDuration;
  running = body.dataset.running !== "false";
  setRunning(running, false);

  document.querySelectorAll("[data-run-toggle]").forEach((button) => {
    button.addEventListener("click", () => setRunning(!running));
  });
}

/* ---------- Toast / actions ---------- */

let snackbarTimer = null;

function showSnackbar(message, icon = "send") {
  let bar = document.getElementById("snackbar");
  if (!bar) {
    bar = document.createElement("div");
    bar.id = "snackbar";
    bar.className = "snackbar";
    bar.setAttribute("role", "status");
    bar.setAttribute("aria-live", "polite");
    document.body.appendChild(bar);
  }
  bar.innerHTML = `<span class="icon" data-icon="${icon}"></span><span>${message}</span>`;
  hydrateIcons(bar);
  bar.classList.add("show");
  window.clearTimeout(snackbarTimer);
  snackbarTimer = window.setTimeout(() => bar.classList.remove("show"), 2600);
}

function flashKey(key) {
  const buttons = document.querySelectorAll(`[data-key="${key}"]`);
  buttons.forEach((button) => {
    button.classList.remove("flash");
    void button.offsetWidth;
    button.classList.add("flash");
    window.setTimeout(() => button.classList.remove("flash"), 440);
  });
  return buttons.length > 0;
}

function initActions() {
  document.addEventListener("click", (event) => {
    const action = event.target.closest("[data-action]");
    if (action) {
      const key = action.dataset.key || "";
      const label = action.dataset.actionLabel || action.dataset.action || "";
      flashKey(key);
      showSnackbar(
        `${key ? `<kbd>${key}</kbd> ` : ""}已触发 ${label}`,
        "send"
      );
      return;
    }
    const toast = event.target.closest("[data-toast]");
    if (toast) {
      showSnackbar(toast.dataset.toast, toast.dataset.toastIcon || "info");
    }
  });

  if (!document.querySelector(".app")) return;
  document.addEventListener("keydown", (event) => {
    if (event.metaKey || event.ctrlKey || event.altKey) return;
    const key = event.key;
    if (!KEY_ACTIONS[key]) return;
    event.preventDefault();
    const label = KEY_ACTIONS[key];
    const found = flashKey(key);
    if (label === "Spare") {
      showSnackbar(`<kbd>${key}</kbd> 尚未分配 · 可在设置中自定义`, "info");
    } else if (found) {
      showSnackbar(`<kbd>${key}</kbd> 已触发 ${label}`, "send");
    } else {
      showSnackbar(`<kbd>${key}</kbd> ${label} · 快捷键已生效`, "send");
    }
  });
}

/* ---------- Settings widgets ---------- */

function initSegments() {
  document.querySelectorAll(".seg").forEach((seg) => {
    seg.addEventListener("click", (event) => {
      const button = event.target.closest("button");
      if (!button) return;
      seg.querySelectorAll("button").forEach((b) => {
        b.classList.toggle("selected", b === button);
        b.setAttribute("aria-pressed", String(b === button));
      });
    });
  });
}

function initSliders() {
  document.querySelectorAll("input[type=range].slider").forEach((input) => {
    const update = () => {
      const min = Number(input.min || 0);
      const max = Number(input.max || 100);
      const value = Number(input.value);
      const pct = ((value - min) / (max - min)) * 100;
      input.style.setProperty("--fill", `${pct}%`);
      document.querySelectorAll("[data-volume-output]").forEach((out) => {
        out.textContent = `${Math.round(value * 100)}%`;
      });
    };
    input.addEventListener("input", update);
    update();
  });
}

/* ---------- View switching (B) ---------- */

function setView(name) {
  document.querySelectorAll("[data-view]").forEach((view) => {
    view.classList.toggle("active", view.dataset.view === name);
  });
  document.querySelectorAll(".rail-nav [data-view-target]").forEach((item) => {
    item.classList.toggle("active", item.dataset.viewTarget === name);
  });
  const view = document.querySelector(`.view[data-view="${name}"]`);
  const title = view?.dataset.title;
  const subtitle = view?.dataset.subtitle;
  document.querySelectorAll("[data-view-title]").forEach((el) => {
    el.textContent = title || "";
  });
  document.querySelectorAll("[data-view-subtitle]").forEach((el) => {
    el.textContent = subtitle || "";
  });
}

function initViews() {
  document.addEventListener("click", (event) => {
    const target = event.target.closest("[data-view-target]");
    if (!target) return;
    event.preventDefault();
    const name = target.dataset.viewTarget;
    if (name === "settings") {
      openOverlay(document.querySelector("#settings-overlay"), target);
      return;
    }
    if (name === "actions") {
      openOverlay(document.querySelector("#actions-overlay"), target);
      return;
    }
    setView(name);
  });
}

/* ---------- Key reference ---------- */

function mountKeyReference() {
  if (document.getElementById("keyref-overlay")) return;
  const keys = Object.keys(KEY_ACTIONS)
    .map((key) => {
      const label = KEY_ACTIONS[key];
      const spare = label === "Spare";
      return `<div class="key-item${spare ? " spare" : ""}">
        <kbd>${key}</kbd><span class="key-text">${spare ? "未分配" : label}</span>
      </div>`;
    })
    .join("");

  const nav = [
    ["Tab", "光标移到下一个输入框"],
    ["Shift+Tab", "光标移到上一个输入框"],
    ["Space", "切换呼号 / 交换信息"],
    [";", "发送呼号 + 交换"],
    ["Enter", "提交当前 QSO"],
    ["Esc", "停止发送，不放弃本轮"]
  ]
    .map(([key, desc]) => {
      const keyHtml = key
        .split("+")
        .map((part) => `<kbd>${part}</kbd>`)
        .join(" + ");
      return `<div class="key-list-row"><span class="desc">${desc}</span><span class="keys">${keyHtml}</span></div>`;
    })
    .join("");

  const markup = `
  <div class="overlay dialog-overlay" id="keyref-overlay" data-overlay aria-hidden="true">
    <div class="scrim" data-close></div>
    <section class="dialog" role="dialog" aria-modal="true" aria-labelledby="keyref-title">
      <div class="dialog-head">
        <span class="dialog-icon"><span class="icon" data-icon="keyboard"></span></span>
        <div class="head-copy">
          <h2 id="keyref-title">键盘速查</h2>
          <p class="sub">功能键直接发送语音；输入框与提交键始终可用。</p>
        </div>
        <button class="icon-btn" data-close aria-label="关闭"><span class="icon" data-icon="close"></span></button>
      </div>
      <div class="dialog-body">
        <p class="dialog-section-label">发送 · F1–F12</p>
        <div class="key-grid">${keys}</div>
        <p class="dialog-section-label">导航与提交</p>
        <div class="key-list">${nav}</div>
        <div class="dialog-note"><span class="icon" data-icon="info"></span><span>F9–F11 默认为空，可在设置中重新分配；所有快捷键都保留现有操作习惯。</span></div>
      </div>
      <div class="dialog-foot">
        <button class="btn btn-text" data-toast="打开功能键自定义面板（原型示意）"><span class="icon" data-icon="tune"></span>自定义功能键</button>
        <span class="spacer"></span>
        <button class="btn btn-filled" data-close>完成</button>
      </div>
    </section>
  </div>`;
  document.body.insertAdjacentHTML("beforeend", markup);
  hydrateIcons(document.getElementById("keyref-overlay"));
}

/* ---------- Scroll + deep links ---------- */

function initLogScroll() {
  document.querySelectorAll(".log-scroll").forEach((el) => {
    window.requestAnimationFrame(() => {
      el.scrollTop = el.scrollHeight;
    });
  });
}

function initDeepLink() {
  const hash = location.hash.replace("#", "");
  if (hash.startsWith("view-")) {
    const name = hash.slice(5);
    if (document.querySelector(`.view[data-view="${name}"]`)) setView(name);
    return;
  }
  const targets = {
    settings: "#settings-overlay",
    keyref: "#keyref-overlay",
    actions: "#actions-overlay",
    score: "#score-overlay"
  };
  const selector = targets[hash];
  if (!selector) return;
  window.setTimeout(() => {
    openOverlay(document.querySelector(selector), null);
  }, 120);
}

/* ---------- Boot ---------- */

document.addEventListener("DOMContentLoaded", () => {
  hydrateIcons();
  initTheme();
  mountKeyReference();
  initTabs();
  initOverlays();
  initTimer();
  initPhaseHint();
  initActions();
  initSegments();
  initSliders();
  initViews();
  initLogScroll();
  initDeepLink();
});
