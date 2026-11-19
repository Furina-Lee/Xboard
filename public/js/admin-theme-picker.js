(() => {
  const template = document.getElementById('xboard-admin-theme-template');
  if (!template) return;

  const builtin = new Map([
    ['default', ['原始主题', '使用 Xboard 后台的原始配色。']],
    ['minimal', ['简约主题', '低饱和青绿、细边框和轻阴影。']],
    ['liquid-glass', ['Liquid Glass', '半透明卡片、柔和光晕和磨砂玻璃效果。']],
  ]);

  class AdminThemePage extends HTMLElement {
    connectedCallback() {
      this.controller = new AbortController();
      this.replaceChildren(template.content.cloneNode(true));
      this.grid = this.querySelector('.xboard-admin-theme-grid');
      this.status = this.querySelector('[role="status"]');
      this.fileInput = this.querySelector('input[type="file"]');
      this.fileInput.addEventListener('change', () => {
        const [file] = this.fileInput.files;
        this.fileInput.value = '';
        if (!file) return;

        this.run(async () => {
          const body = new FormData();
          body.append('theme', file);
          this.render(await this.request('/upload', body));
          return '主题校验通过并已保存。';
        });
      });
      this.run(async () => {
        this.render(await this.request());
        return '';
      }, true);
    }

    openUpload() {
      if (this.getAttribute('aria-busy') !== 'true') this.fileInput?.click();
    }

    disconnectedCallback() {
      this.controller.abort();
    }

    async request(action = '', body) {
      let session;
      try {
        session = JSON.parse(localStorage.getItem('XBOARD_ACCESS_TOKEN'));
      } catch {
        session = null;
      }
      if (typeof session?.value !== 'string' || (session.expire && session.expire <= Date.now())) {
        throw new Error('登录已过期，请重新登录。');
      }

      const headers = { Accept: 'application/json', Authorization: session.value };
      if (typeof body === 'string') headers['Content-Type'] = 'application/json';
      const result = await fetch(template.dataset.endpoint + action, {
        headers, body, method: body ? 'POST' : 'GET', cache: 'no-store', signal: this.controller.signal,
      });
      if (result.status === 401) throw new Error('登录已过期，请重新登录。');
      const data = await result.json();
      if (!result.ok) throw new Error(Object.values(data.errors || {}).flat()[0] || data.message || '操作失败');
      return data;
    }

    render(data) {
      this.grid.replaceChildren(...data.themes.map((id) => {
        const [name, description] = builtin.get(id) ?? [id, '已上传的自定义色板。'];
        const card = document.createElement('article');
        card.className = 'xboard-admin-theme-card bg-card rounded-xl';
        const preview = document.createElement('div');
        preview.className = 'xboard-admin-theme-swatch';
        preview.dataset.style = builtin.has(id) ? id : 'custom';
        preview.setAttribute('aria-hidden', 'true');
        const title = document.createElement('h2');
        title.textContent = name;
        const summary = document.createElement('p');
        summary.className = 'text-muted-foreground';
        summary.textContent = description;
        const button = document.createElement('button');
        button.type = 'button';
        button.className = 'xboard-admin-theme-button';
        const active = id === data.selected;
        button.textContent = active ? '当前主题' : '应用到所有管理员';
        button.disabled = active;
        button.addEventListener('click', () => this.run(async () => {
          await this.request('/select', JSON.stringify({ id }));
          window.location.reload();
          return '主题已更新。';
        }));
        card.append(preview, title, summary, button);
        return card;
      }));
    }

    async run(action, initial = false) {
      if (this.getAttribute('aria-busy') === 'true') return;
      this.setAttribute('aria-busy', 'true');
      const buttons = initial ? [] : [...this.querySelectorAll('button:not(:disabled)')];
      buttons.forEach((button) => { button.disabled = true; });
      this.status.textContent = initial ? '正在加载主题…' : '处理中…';
      try {
        this.status.textContent = await action();
      } catch (error) {
        if (error.name !== 'AbortError') this.status.textContent = error.message;
      } finally {
        buttons.forEach((button) => { button.disabled = false; });
        this.removeAttribute('aria-busy');
      }
    }
  }

  customElements.define('xboard-admin-theme-page', AdminThemePage);
})();
