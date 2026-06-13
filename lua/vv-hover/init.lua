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
---@field hover_delay integer   鼠标停留触发延迟（ms） @default 500
---@field close_delay integer   鼠标移开后延迟关闭时间（ms） @default 300

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

---@class VVHoverModule
---@field setup fun(opts?: VVHoverConfig)
---@field enable fun()
---@field disable fun()
---@field set_provider fun(fn: VVHoverProvider)
---@field show fun()
---@field hide fun()
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
    hover_delay = 500,        -- 鼠标停留触发延迟（ms）
    close_delay = 300,        -- 鼠标移开后延迟关闭时间（ms）
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

---获取当前配置
---@return table
function M.get_config()
  return vim.deepcopy(config)
end

return M
