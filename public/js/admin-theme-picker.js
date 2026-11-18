(() => {
  const picker = document.getElementById('xboard-admin-theme-picker');
  if (!picker) return;
  const { endpoint } = picker.dataset;
  const select = document.getElementById('xboard-admin-theme-choice');
  const selectForm = document.getElementById('xboard-admin-theme-select');
  const uploadForm = document.getElementById('xboard-admin-theme-upload');
  const status = document.getElementById('xboard-admin-theme-status');
  let token = null;

  function sessionToken() {
    try {
      const session = JSON.parse(localStorage.getItem('XBOARD_ACCESS_TOKEN'));
      return typeof session?.value === 'string' && (!session.expire || session.expire > Date.now())
        ? session.value : null;
    } catch {
      return null;
    }
  }

  async function request(action = '', body) {
    const headers = { Accept: 'application/json', Authorization: token };
    if (typeof body === 'string') headers['Content-Type'] = 'application/json';
    const result = await fetch(endpoint + action, { headers, body, method: body ? 'POST' : 'GET', cache: 'no-store' });
    const data = await result.json();
    if (!result.ok) throw new Error(Object.values(data.errors || {}).flat()[0] || data.message || '操作失败');
    return data;
  }

  function render(data) {
    select.replaceChildren(...data.themes.map((id) => {
      const name = id === 'default' ? '原始主题' : id === 'minimal' ? '简约主题' : id;
      return new Option(name, id, false, id === data.selected);
    }));
  }

  async function refreshSession() {
    const current = sessionToken();
    if (current === token) return;
    token = current;
    picker.hidden = true;
    if (!current) return;
    try {
      const data = await request();
      if (token !== current) return;
      if (data.selected !== picker.dataset.selected) {
        window.location.reload();
        return;
      }
      render(data);
      picker.hidden = false;
    } catch {
      // The admin endpoint is authoritative, including on the login page.
    }
  }

  function onSubmit(form, action, body, onSuccess) {
    form.addEventListener('submit', async (event) => {
      event.preventDefault();
      const button = form.querySelector('button');
      button.disabled = true;
      status.textContent = '处理中…';
      try {
        await onSuccess(await request(action, body()));
      } catch (error) {
        status.textContent = error.message;
      } finally {
        button.disabled = false;
      }
    });
  }

  onSubmit(selectForm, '/select', () => JSON.stringify({ id: select.value }), () => window.location.reload());
  onSubmit(uploadForm, '/upload', () => new FormData(uploadForm), (data) => {
    render(data);
    uploadForm.reset();
    status.textContent = '主题校验通过并已保存，可从列表选择。';
  });
  refreshSession();
  window.setInterval(refreshSession, 1500);
})();
