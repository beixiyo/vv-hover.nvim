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
---@class VVHoverTimingConfig
---@field hover_delay integer   鼠标停留触发延迟（ms） @default 250
---@field close_delay integer   鼠标移开后延迟关闭时间（ms） @default 50

---@class VVHoverUIConfig
---@field border string @default 'rounded'
---@field max_width integer @default 80
---@field max_height integer @default 20
---@field focusable boolean @default true
---@field zindex integer @default 150
---@field relative '"mouse"'|'"cursor"'|'"editor"' @default 'mouse'

---@class VVHoverBehaviorConfig
---@field close_on_move boolean @default true
---@field close_on_insert boolean @default false
---@field only_normal_buf boolean @default true

---@class VVHoverProviderResult
---@field lines string[]
---@field filetype string

---@class VVHoverMousePos
---@field winid integer
---@field line integer
---@field column integer

---@class VVHoverProviderCtx
---@field bufnr integer
---@field winid integer
---@field row integer
---@field col integer
---@field line_text string
---@field mouse_pos VVHoverMousePos
---@field lsp_clients vim.lsp.Client[]

---@alias VVHoverProvider fun(ctx: VVHoverProviderCtx, callback?:fun(result: VVHoverProviderResult|nil)): any

---@class VVHoverView
---@field setup fun(cfg: VVHoverConfig)
---@field open fun(lines: string[], filetype: string, winid?: integer): (integer|nil, integer|nil)
---@field close fun()
---@field is_open fun(): boolean
---@field is_mouse_inside fun(pos: VVHoverMousePos|nil): boolean
---@field scroll fun(direction: '"up"'|'"down"')

---@class VVHoverController
---@field setup fun(cfg: VVHoverConfig, view: VVHoverView, provider: VVHoverProvider)
---@field enable fun()
---@field disable fun()
---@field is_enabled fun(): boolean
---@field set_provider fun(fn: VVHoverProvider)
---@field show fun()

---@class VVHoverConfig
---@field enabled boolean @default true
---@field timing VVHoverTimingConfig
---@field ui VVHoverUIConfig
---@field behavior VVHoverBehaviorConfig
---@field provider VVHoverProvider|nil @default nil
---@field keymap_focus string|false  聚焦悬停浮窗的全局键；false 则用原生 `<C-w>w` 进窗 @default false

---@class VVHoverModule
---@field setup fun(opts?: VVHoverConfig)
---@field enable fun()
---@field disable fun()
---@field set_provider fun(fn: VVHoverProvider)
---@field show fun()
---@field hide fun()
---@field focus fun(): boolean
---@field get_config fun(): VVHoverConfig

---@type VVHoverModule
local M = {}

--- 默认配置
---@type VVHoverConfig
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
  -- 函数签名：function(ctx) -> { lines = string[], filetype = string } | nil
  -- ctx 包含：bufnr, winid, row, col, line_text, mouse_pos, lsp_clients
  provider = nil,
}

-- 内部状态
---@type VVHoverConfig
local config = default_config
---@type VVHoverController|nil
local controller = nil
---@type VVHoverView|nil
local view = nil
---@type VVHoverProvider|nil
local provider = nil

---设置插件配置
---@param opts VVHoverConfig|nil 配置选项
function M.setup(opts)
  opts = opts or {}

  -- 合并配置（vim.tbl_deep_extend 已递归处理嵌套表）
  config = vim.tbl_deep_extend("force", default_config, opts)

  -- 初始化模块
  controller = require("vv-hover.controller")
  view = require("vv-hover.view")

  -- 设置默认 provider（如果未指定）
  if not config.provider then
    local lsp_provider = require("vv-hover.providers.lsp")
    provider = lsp_provider.new(config)
  else
    provider = config.provider
  end

  -- 初始化 controller 和 view
  controller.setup(config, view, provider)
  view.setup(config)

  -- 如果启用，自动启动
  if config.enabled then
    M.enable()
  end

  vim.api.nvim_create_user_command('VVHoverEnable', function() M.enable() end, {})
  vim.api.nvim_create_user_command('VVHoverDisable', function() M.disable() end, {})
  vim.api.nvim_create_user_command('VVHoverToggle', function() M.toggle() end, {})
  vim.api.nvim_create_user_command('VVHoverFocus', function() M.focus() end, {})

  -- 可选「直达聚焦浮窗」全局键（单一生命周期，遵循 AGENTS.md setup 例外；默认 false 走原生 <C-w>w）
  if type(config.keymap_focus) == "string" and config.keymap_focus ~= "" then
    vim.keymap.set("n", config.keymap_focus, M.focus, { desc = "vv-hover: 聚焦悬停浮窗", silent = true })
  end
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
end

---设置自定义内容提供者
---@param fn function 内容提供者函数
function M.set_provider(fn)
  provider = fn
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
  if view then
    view.close()
  end
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
