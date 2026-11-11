// 谛听 (DITING) 开发者工具箱通用 DOM 辅助
// 所有动态文本一律走 textContent / createTextNode，避免路径、域名中的特殊字符破坏 HTML。

window.UI = {
  el(tag, props = {}, ...children) {
    const node = document.createElement(tag);
    Object.entries(props || {}).forEach(([key, value]) => {
      if (value === undefined || value === null) return;
      if (key === 'className') {
        node.className = value;
      } else if (key === 'text') {
        node.textContent = value;
      } else if (key === 'dataset') {
        Object.assign(node.dataset, value);
      } else if (key.startsWith('on') && typeof value === 'function') {
        node.addEventListener(key.slice(2).toLowerCase(), value);
      } else if (key in node && key !== 'style') {
        node[key] = value;
      } else {
        node.setAttribute(key, value);
      }
    });

    const append = (child) => {
      if (child === null || child === undefined || child === false) return;
      if (Array.isArray(child)) {
        child.forEach(append);
        return;
      }
      node.appendChild(child instanceof Node ? child : document.createTextNode(String(child)));
    };
    children.forEach(append);
    return node;
  },

  clear(node) {
    if (node) node.textContent = '';
  },

  stats(container, items) {
    if (!container) return;
    this.clear(container);
    items.forEach((item) => {
      container.appendChild(
        this.el('div', { className: 'stat-box' },
          this.el('span', { className: 'stat-label', text: item.label }),
          this.el('span', {
            className: `stat-value${item.fail ? ' is-fail' : ''}`,
            text: item.value === undefined || item.value === null ? '—' : String(item.value),
          }),
        ),
      );
    });
  },

  row(tbody, cells) {
    const tr = document.createElement('tr');
    cells.forEach((cell) => {
      const td = document.createElement('td');
      if (cell instanceof Node) {
        td.appendChild(cell);
      } else if (cell && typeof cell === 'object') {
        if (cell.className) td.className = cell.className;
        if (cell.node instanceof Node) td.appendChild(cell.node);
        else td.textContent = cell.text === undefined ? '' : String(cell.text);
      } else {
        td.textContent = cell === undefined || cell === null ? '' : String(cell);
      }
      tr.appendChild(td);
    });
    tbody.appendChild(tr);
    return tr;
  },

  badge(text, className = 'badge') {
    return this.el('span', { className, text });
  },

  button(text, onClick, className = 'btn btn-sm btn-ghost') {
    return this.el('button', { className, text, onclick: onClick });
  },

  note(text, className = 'hint-text') {
    return this.el('p', { className, text });
  },
};
