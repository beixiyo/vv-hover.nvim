-- ================================
-- vv-hover.nvim - 自动 Hover 插件
-- ================================
-- 基于鼠标位置的自动 LSP Hover 显示
--
-- 特性：
-- - 鼠标悬停自动显示 LSP 文档
-- - 可自定义内容提供者（支持非 LSP 内容）
-- - 完整的时序配置（延迟、防抖、节流等）
-- - 单一职责的模块化架构
require('vv-hover.types')
---@class VVHover.Module
---@field setup fun(opts?: VVHover.ConfigOptions)
---@field enable fun()
---@field disable fun()
---@field set_provider fun(fn: VVHover.Provider)
---@field show fun()
---@field hide fun()
---@field focus fun(): boolean
---@field get_config fun(): VVHover.Config
---@field toggle fun()
local M = {}

--- 默认配置
---@type VVHover.Config
local default_config = {
  -- 基础开关
  enabled = true,

  -- 时序配置
  timing = {
    hover_delay = 250,        -- 鼠标停留触发延迟（ms）
    close_delay = 50,         -- 鼠标移开后延迟关闭时间（ms）
  },

  -- UI 配置
  ui = {
    border = "rounded",
    max_width = 80,
    max_height = 20,
    focusable = true,
    zindex = 150,
    relative = "mouse",       -- 浮窗相对位置：mouse | cursor | editor
  },

  -- 行为配置
  behavior = {
    close_on_move = true,     -- 鼠标移出符号位置时自动关闭
    close_on_insert = false,  -- 进入插入模式时关闭
    only_normal_buf = true,   -- 只在普通文件 buffer 中启用
  },

  -- 聚焦浮窗的全局键：false=用原生 <C-w>w 进窗；设字符串则注册该键直达聚焦
  keymap_focus = false,

  -- 内容提供者：nil 表示使用默认 LSP provider
  -- 同步返回 result|nil；异步返回 true, cancel? 并通过 callback 投递 result|nil
  -- ctx 包含：bufnr, winid, row, col, line_text, mouse_pos, lsp_clients
  provider = nil,
}

-- 内部状态
---@type VVHover.Config
local config = default_config
---@type VVHover.Controller|nil
local controller = nil
---@type VVHover.View|nil
local view = nil
---设置插件配置
---@param opts VVHover.ConfigOptions|nil 配置选项
function M.setup(opts)
  opts = opts or {}

  if controller and controller.is_enabled() then controller.disable() end
  require('vv-hover.mappings').restore_focus()

  -- 合并配置（vim.tbl_deep_extend 已递归处理嵌套表）
  config = vim.tbl_deep_extend("force", default_config, opts)

  -- 初始化模块
  controller = require("vv-hover.controller")
  view = require("vv-hover.view")

  -- 设置默认 provider（如果未指定）
  local next_provider ---@type VVHover.Provider
  if config.provider then
    next_provider = config.provider
  else
    local lsp_provider = require("vv-hover.providers.lsp")
    next_provider = lsp_provider.new(config)
  end
  local resolved_provider = assert(next_provider)

  -- 初始化 controller 和 view
  controller.setup(config, view, resolved_provider)
  view.setup(config)

  -- 如果启用，自动启动
  if config.enabled then
    M.enable()
  end

  vim.api.nvim_create_user_command('VVHoverEnable', function() M.enable() end, { force = true })
  vim.api.nvim_create_user_command('VVHoverDisable', function() M.disable() end, { force = true })
  vim.api.nvim_create_user_command('VVHoverToggle', function() M.toggle() end, { force = true })
  vim.api.nvim_create_user_command('VVHoverFocus', function() M.focus() end, { force = true })

  require('vv-hover.mappings').configure_focus(config.keymap_focus, M.focus)
end

---启用插件
function M.enable()
  if controller then
    controller.enable()
  end
end

---禁用插件
function M.disable()
  if controller then
    controller.disable()
  end
  require('vv-hover.mappings').restore_focus()
end

---设置自定义内容提供者
---@param fn VVHover.Provider 内容提供者函数
function M.set_provider(fn)
  if controller then
    controller.set_provider(fn)
  end
end

---手动显示 hover（基于当前鼠标位置）
function M.show()
  if controller then
    controller.show()
  end
end

---切换启用/禁用
--- 以 controller 的真实状态为唯一来源，避免 enable/disable 不更新 config.enabled
--- 导致的状态漂移（:VVHoverDisable 后 toggle 变成无操作的 bug）。
function M.toggle()
  if controller and controller.is_enabled() then
    M.disable()
  else
    M.enable()
  end
end

---手动关闭 hover
function M.hide()
  if controller then controller.hide() end
end

---聚焦当前 hover 浮窗（若打开），进窗后可用 `<C-e>`/`<C-y>` 滚动、`v`+`y` 复制、`q`/`<Esc>` 关闭。
--- 即便 `ui.focusable=false` 也能进（走 `nvim_set_current_win`）。
---@return boolean focused 浮窗存在并已聚焦
function M.focus()
  if not view then
    return false
  end

  local win, bufnr = view.get_current()
  if not (win and vim.api.nvim_win_is_valid(win)) then
    return false
  end

  -- close_events 置空 → 浮窗不会自动关，进窗后给 q/<Esc> 退出口
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    for _, key in ipairs({ "q", "<Esc>" }) do
      pcall(vim.keymap.set, "n", key, function() M.hide() end,
        { buffer = bufnr, nowait = true, silent = true, desc = "vv-hover: 关闭浮窗" })
    end
  end

  vim.api.nvim_set_current_win(win)
  return true
end

---获取当前配置
---@return table
function M.get_config()
  return vim.deepcopy(config)
end

return M
