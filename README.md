<div align="center">
  <h1>vv-hover.nvim</h1>
  <p>English | <a href="./README.zh-CN.md">中文</a></p>
  <img src="https://github.com/beixiyo/vv-hover.nvim/releases/download/assets-2026-07-25/vv-hover.png" alt="vv-hover demo" width="900" />
  <p>Want my Neovim config? See <a href="https://github.com/beixiyo/dotfiles">dotfiles</a></p>
  <em>Automatic LSP hover at the mouse position: reveal documentation by hovering and extend it with custom providers</em>
  <p>
    <img src="https://img.shields.io/badge/Neovim-0.12+-57A143?style=flat-square&logo=neovim&logoColor=white" alt="Requires Neovim 0.12+" />
    <img src="https://img.shields.io/badge/Lua-2C2D72?style=flat-square&logo=lua&logoColor=white" alt="Lua" />
    <img src="https://img.shields.io/badge/depends-vv--utils.nvim-2ea44f?style=flat-square" alt="Depends on vv-utils.nvim" />
  </p>
</div>

---

## Installation

Requires Neovim 0.12 or newer

```lua
{
  'beixiyo/vv-hover.nvim',
  event = 'VeryLazy',
  dependencies = { 'beixiyo/vv-utils.nvim' },
  ---@type HoverConfig
  opts = {
    enabled = true,
    timing = {
      hover_delay = 250,
      close_delay = 50,
    },
    ui = {
      border = 'rounded',
      max_width = 80,
      max_height = 20,
      focusable = true,
      zindex = 150,
      relative = 'mouse', -- 'mouse' | 'cursor' | 'editor'
    },
    behavior = {
      close_on_move = true,
      close_on_insert = false,
      only_normal_buf = true,
    },
  },
}
```

## Configuration

### Timing

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `timing.hover_delay` | `integer` | `250` | Delay before hover opens, in milliseconds |
| `timing.close_delay` | `integer` | `50` | Delay before the window closes after the mouse leaves |

### UI

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `ui.border` | `string` | `'rounded'` | Floating-window border style |
| `ui.max_width` | `integer` | `80` | Maximum width |
| `ui.max_height` | `integer` | `20` | Maximum height |
| `ui.focusable` | `boolean` | `true` | Whether the floating window can receive focus |
| `ui.zindex` | `integer` | `150` | Floating-window stacking level |
| `ui.relative` | `string` | `'mouse'` | Positioning reference: `'mouse'`, `'cursor'`, or `'editor'` |

### Behavior

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `behavior.close_on_move` | `boolean` | `true` | Closes when the mouse leaves the symbol |
| `behavior.close_on_insert` | `boolean` | `false` | Closes when entering Insert mode |
| `behavior.only_normal_buf` | `boolean` | `true` | Enables hover only in normal file buffers, skipping terminals and `nofile` buffers |
| `provider` | `HoverProvider?` | `nil` | Custom content provider; `nil` uses the default LSP provider, and `set_provider()` can also replace it |
| `keymap_focus` | `string \| false` | `false` | Optional global key that focuses the hover directly; use native `<C-w>w` when disabled |

### Using the floating window from the keyboard

The window is focusable by default. Enter it with standard Neovim window commands, then scroll, select, and copy normally.

| Action | Key | Description |
|--------|-----|-------------|
| **Focus** | `<C-w>w` | Cycle to the floating window; use `<C-w>p` to return |
| **Focus directly** | `:VVHoverFocus` / `keymap_focus` | Avoid cycling through multiple windows |
| **Scroll** | `<C-e>` / `<C-y>`, `j` / `k`, `<C-d>` / `<C-u>` | Standard scrolling keys |
| **Copy** | `v`, move, then `y` | Standard Visual-mode selection and yank |
| **Close** | `q` / `<Esc>` or `<C-w>q` | `q` and `<Esc>` are mapped after focusing the window |

`VVHoverFocus` and `M.focus()` can enter the window even when `ui.focusable = false`, because they use `nvim_set_current_win` internally. Native window commands such as `<C-w>w` work only when `focusable = true`.

To scroll with `<C-e>` and `<C-y>` without focusing the window, route those keys to the hover while it is open using `view.is_open()` and `view.scroll()`.

### Custom provider

The default provider uses LSP hover. A synchronous provider returns its result directly, or `nil` when it has no content:

```lua
require('vv-hover').set_provider(function(ctx)
  -- ctx: { bufnr, winid, row, col, line_text, mouse_pos, lsp_clients }
  return { lines = { 'Custom content' }, filetype = 'markdown' }
end)
```

An asynchronous provider returns the literal `true`, delivers its result through the callback, and may return an idempotent physical cancel function as its second result:

```lua
require('vv-hover').set_provider(function(ctx, callback)
  local timer = vim.defer_fn(function()
    callback({ lines = { 'Async content' }, filetype = 'markdown' })
  end, 100)

  return true, function()
    if not timer:is_closing() then
      timer:stop()
      timer:close()
    end
  end
end)
```

`true` is reserved as the asynchronous sentinel; other truthy values are not treated as async. The controller calls the cancel function when a newer hover supersedes the request or the hover lifecycle closes. Cancellation is best-effort, so callbacks must still tolerate arriving after cancellation; the controller also rejects stale results logically.
