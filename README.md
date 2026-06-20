<h1 align="center">vv-hover.nvim</h1>

<p align="center">
  <em>基于鼠标位置的自动 LSP Hover — 悬停即显文档，可扩展 Provider</em>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Neovim-0.10+-57A143?style=flat-square&logo=neovim&logoColor=white" alt="Requires Neovim 0.10+" />
  <img src="https://img.shields.io/badge/Lua-2C2D72?style=flat-square&logo=lua&logoColor=white" alt="Lua" />
  <img src="https://img.shields.io/badge/zero_deps-✓-2ea44f?style=flat-square" alt="Zero Dependencies" />
</p>

---

## 安装

```lua
{
  'beixiyo/vv-hover.nvim',
  event = 'VeryLazy',
  ---@type HoverConfig
  opts = {
    enabled = true,

    timing = {
      hover_delay = 250,       -- 鼠标停留触发延迟（ms）
      close_delay = 50,        -- 鼠标移开后延迟关闭（ms）
    },

    ui = {
      border = 'rounded',      -- 边框样式
      max_width = 80,
      max_height = 20,
      focusable = true,
      zindex = 150,
      relative = 'mouse',     -- 浮窗相对位置：'mouse' | 'cursor' | 'editor'
    },

    behavior = {
      close_on_move = true,    -- 鼠标移出符号位置时自动关闭
      close_on_insert = false, -- 进入插入模式时关闭
      only_normal_buf = true,  -- 只在普通文件 buffer 中启用
    },
  },
}
```

## 配置

### 时序

| 选项 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `timing.hover_delay` | `integer` | `250` | 鼠标悬停多久后触发 hover（ms） |
| `timing.close_delay` | `integer` | `50` | 鼠标移开后延迟多久关闭浮窗（ms） |

### UI

| 选项 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `ui.border` | `string` | `'rounded'` | 浮窗边框样式 |
| `ui.max_width` | `integer` | `80` | 最大宽度 |
| `ui.max_height` | `integer` | `20` | 最大高度 |
| `ui.focusable` | `boolean` | `true` | 浮窗是否可聚焦 |
| `ui.zindex` | `integer` | `150` | 浮窗层级 |
| `ui.relative` | `string` | `'mouse'` | 浮窗定位基准：`'mouse'` / `'cursor'` / `'editor'` |

### 行为

| 选项 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `behavior.close_on_move` | `boolean` | `true` | 鼠标移出符号位置时自动关闭 |
| `behavior.close_on_insert` | `boolean` | `false` | 进入插入模式时关闭 |
| `behavior.only_normal_buf` | `boolean` | `true` | 只在普通文件 buffer 中启用（跳过 terminal / nofile 等） |
| `provider` | `HoverProvider?` | `nil` | 自定义内容提供者（`nil` 使用默认 LSP provider），也可通过 `set_provider()` 设置 |
| `keymap_focus` | `string \| false` | `false` | 「直达聚焦浮窗」的全局键；`false` 时用原生 `<C-w>w` 进窗，设字符串（如 `'<leader>k'`）则额外注册该键一键进窗 |

### 键盘操作浮窗（进窗滚动 / 复制）

浮窗默认 `focusable = true`，可以用 **Neovim 官方的窗口切换键进窗**，进窗后即可滚动长文档、选中复制：

| 操作 | 键 | 说明 |
|------|-----|------|
| **进窗** | `<C-w>w` | Neovim 官方「切换到下一个窗口」键，轮转到浮窗；`<C-w>p` 回到原窗口 |
| **直达进窗** | `:VVHoverFocus` / `keymap_focus` | 多窗口时 `<C-w>w` 需轮转，配 `keymap_focus` 可一键直达 |
| **滚动** | `<C-e>` / `<C-y>`、`j` / `k`、`<C-d>` / `<C-u>` | 标准滚动键 |
| **复制** | `v` + 移动 + `y`（或 `V`、`y`） | 标准可视选择复制 |
| **关闭** | `q` / `<Esc>`（进窗后自动绑定）、`<C-w>q` | |

> `:VVHoverFocus`（及 `M.focus()`）即便在 `ui.focusable = false` 下也能进窗（内部走 `nvim_set_current_win`）；而 `<C-w>w` 这类原生窗口切换键只对 `focusable = true` 的浮窗生效

如果想让 `<C-e>` / `<C-y>` 在**不进窗**时也能滚动浮窗，可在 hover 打开时把这两个键路由到浮窗滚动（参考插件的 `view.is_open()` / `view.scroll()`）

### 自定义 Provider

默认使用 LSP hover。可通过 `set_provider` 替换为自定义内容源：

```lua
require('vv-hover').set_provider(function(ctx, callback)
  -- ctx: { bufnr, winid, row, col, line_text, mouse_pos, lsp_clients }
  callback({ lines = { '自定义内容' }, filetype = 'markdown' })
  return true -- 异步 provider 返回 true
end)
```
