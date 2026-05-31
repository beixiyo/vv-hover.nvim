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
      hover_delay = 500,       -- 鼠标停留触发延迟（ms）
      close_delay = 300,       -- 鼠标移开后延迟关闭（ms）
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
| `timing.hover_delay` | `integer` | `500` | 鼠标悬停多久后触发 hover（ms） |
| `timing.close_delay` | `integer` | `300` | 鼠标移开后延迟多久关闭浮窗（ms） |

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

### 自定义 Provider

默认使用 LSP hover。可通过 `set_provider` 替换为自定义内容源：

```lua
require('vv-hover').set_provider(function(ctx, callback)
  -- ctx: { bufnr, winid, row, col, line_text, mouse_pos, lsp_clients }
  callback({ lines = { '自定义内容' }, filetype = 'markdown' })
  return true -- 异步 provider 返回 true
end)
```
