# vv-hover.nvim

一个基于鼠标位置的自动 LSP Hover 显示插件，兼容 LazyVim。

## 特性

- 🖱️ **基于鼠标位置**：完全基于鼠标位置显示 hover，而不是光标位置
- ⚡ **自动触发**：鼠标悬停在符号上停留一段时间后自动显示 LSP 文档
- 🔧 **可扩展**：支持自定义内容提供者，不限于 LSP
- ⏱️ **完整时序控制**：可配置延迟、防抖、节流、关闭延迟等
- 🎨 **单一职责架构**：模块化设计，易于维护和扩展
- 🔒 **竞态安全**：使用 token 机制解决异步请求竞态问题

## 安装

lazy.nvim：

```lua
{
  'beixiyo/vv-hover.nvim',
  event = 'VeryLazy',
  opts = {},
}
```

## 配置

### 基础配置

```lua
require("vv-hover").setup({
  enabled = true,
  
  -- 时序配置
  timing = {
    hover_delay = 500,        -- 鼠标停留触发延迟（ms）
    close_delay = 300,        -- 鼠标移开后延迟关闭时间（ms）
    min_show_time = 0,        -- 最小显示时长（ms）
  },
  
  -- UI 配置
  ui = {
    border = "rounded",       -- 边框样式
    max_width = 80,           -- 最大宽度
    max_height = 20,          -- 最大高度
    focusable = true,         -- 是否可聚焦
    zindex = 150,             -- 浮窗层级
    relative = "mouse",       -- 浮窗相对位置：mouse | cursor | editor
  },
  
  -- 行为配置
  behavior = {
    close_on_move = true,     -- 鼠标移出符号位置时自动关闭
    close_on_insert = false,  -- 进入插入模式时关闭
    only_normal_buf = true,   -- 只在普通文件 buffer 中启用
  },
})
```

### 自定义内容提供者

你可以提供自定义函数来控制显示的内容：

```lua
local hover = require("vv-hover")

hover.setup({
  -- ... 其他配置
})

-- 设置自定义 provider
hover.set_provider(function(ctx)
  -- ctx 包含：
  --   bufnr: buffer 编号
  --   winid: 窗口 ID
  --   row: 行号（1-based）
  --   col: 列号（1-based）
  --   line_text: 当前行文本
  --   mouse_pos: 鼠标位置信息
  --   lsp_clients: LSP 客户端列表
  
  -- 返回显示内容
  return {
    lines = { "自定义内容", "第二行" },
    filetype = "markdown",  -- 可选，默认 "markdown"
  }
end)
```

### 异步 Provider

对于异步内容获取（如 LSP），provider 函数应该接受一个 callback：

```lua
hover.set_provider(function(ctx, callback)
  -- 异步获取内容
  some_async_function(ctx, function(result)
    callback({
      lines = result.lines,
      filetype = result.filetype,
    })
  end)
  
  return true  -- 返回 true 表示这是异步 provider
end)
```

## API

### `setup(opts)`

初始化并配置插件。

### `enable()`

启用插件。

### `disable()`

禁用插件。

### `set_provider(fn)`

设置自定义内容提供者。

### `show()`

手动显示 hover（基于当前鼠标位置）。

### `hide()`

手动关闭 hover。

### `get_config()`

获取当前配置。

## 架构

插件采用单一职责原则，分为以下模块：

- **`init.lua`**：插件入口，提供公共 API
- **`controller.lua`**：处理鼠标事件、定时器、状态管理
- **`view.lua`**：负责浮窗的打开和关闭
- **`providers/lsp.lua`**：默认 LSP 内容提供者

## Testing

Smoke test (zero deps, runs in `-u NONE`):

```bash
nvim --headless -u NONE -l tests/test_smoke.lua
```

Expected: trailing line `X passed, 0 failed`.
