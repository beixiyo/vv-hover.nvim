-- ================================
-- vv-hover.nvim 使用示例
-- ================================

local hover = require("vv-hover")

-- ================================
-- 示例 1：基础配置
-- ================================
hover.setup({
  enabled = true,
  timing = {
    hover_delay = 500,
  },
})

-- ================================
-- 示例 2：完整配置
-- ================================
hover.setup({
  enabled = true,
  timing = {
    hover_delay = 500,
    debounce_ms = 50,
    close_delay = 200,
  },
  ui = {
    border = "single",
    max_width = 100,
    max_height = 30,
  },
  behavior = {
    close_on_move = true,
    close_on_insert = true,
  },
})

-- ================================
-- 示例 3：自定义同步 Provider
-- ================================
hover.setup({})

hover.set_provider(function(ctx)
  -- 显示当前行的信息
  local line = ctx.line_text or ""
  return {
    lines = {
      string.format("行号: %d", ctx.row),
      string.format("列号: %d", ctx.col),
      string.format("内容: %s", line:sub(1, 50)),
    },
    filetype = "markdown",
  }
end)

-- ================================
-- 示例 4：自定义异步 Provider
-- ================================
hover.setup({})

hover.set_provider(function(ctx, callback)
  -- 模拟异步操作
  vim.defer_fn(function()
    callback({
      lines = { "异步获取的内容" },
      filetype = "markdown",
    })
  end, 100)

  return true  -- 返回 true 表示这是异步 provider
end)

-- ================================
-- 示例 5：运行时控制
-- ================================
hover.setup({ enabled = false })

-- 稍后启用
vim.defer_fn(function()
  hover.enable()
end, 1000)

-- 禁用
hover.disable()

-- 手动显示
hover.show()

-- 手动关闭
hover.hide()
