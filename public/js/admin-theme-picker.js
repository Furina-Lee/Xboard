(() => {
  const { themes, siteTheme } = document.currentScript.dataset;
  const themeUrls = JSON.parse(themes);
  const stylesheet = document.getElementById('xboard-admin-theme-css');
  const storageKey = 'xboard.admin.theme';
  const hasTheme = (id) => Object.prototype.hasOwnProperty.call(themeUrls, id);
  let choice = '';

  try {
    const saved = localStorage.getItem(storageKey);
    if (saved === 'default' || hasTheme(saved)) choice = saved;
  } catch {
    // Theme selection still works for the current page.
  }

  function applyTheme() {
    const theme = choice || siteTheme;
    if (hasTheme(theme)) {
      if (stylesheet.getAttribute('href') !== themeUrls[theme]) stylesheet.href = themeUrls[theme];
      document.documentElement.dataset.adminTheme = theme;
    } else {
      stylesheet.removeAttribute('href');
      delete document.documentElement.dataset.adminTheme;
    }
  }

  applyTheme();
  document.addEventListener('DOMContentLoaded', () => {
    const picker = document.getElementById('xboard-admin-theme-picker');
    const select = document.getElementById('xboard-admin-theme-choice');
    select.value = choice;
    select.addEventListener('change', () => {
      choice = select.value;
      applyTheme();
      try {
        if (choice) localStorage.setItem(storageKey, choice);
        else localStorage.removeItem(storageKey);
      } catch {
        // Keep the selection active until this page is closed.
      }
    });
    picker.hidden = false;
  }, { once: true });
})();
