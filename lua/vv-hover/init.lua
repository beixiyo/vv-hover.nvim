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
---@class HoverTimingConfig
---@field hover_delay integer   鼠标停留触发延迟（ms）
---@field close_delay integer   鼠标移开后延迟关闭时间（ms）
---@field min_show_time integer 最小显示时长（ms）

---@class HoverUIConfig
---@field border string
---@field max_width integer
---@field max_height integer
---@field focusable boolean
---@field zindex integer
---@field relative '"mouse"'|'"cursor"'|'"editor"'

---@class HoverBehaviorConfig
---@field close_on_move boolean
---@field close_on_insert boolean
---@field only_normal_buf boolean

---@class HoverProviderResult
---@field lines string[]
---@field filetype string

---@class HoverMousePos
---@field winid integer
---@field line integer
---@field column integer

---@class HoverProviderCtx
---@field bufnr integer
---@field winid integer
---@field row integer
---@field col integer
---@field line_text string
---@field mouse_pos HoverMousePos
---@field lsp_clients vim.lsp.Client[]

---@alias HoverProvider fun(ctx: HoverProviderCtx, callback?:fun(result: HoverProviderResult|nil)): any

---@class HoverView
---@field setup fun(cfg: HoverConfig)
---@field open fun(lines: string[], filetype: string): (integer|nil, integer|nil)
---@field close fun()
---@field is_open fun(): boolean
---@field is_mouse_inside fun(pos: HoverMousePos|nil): boolean
---@field scroll fun(direction: '"up"'|'"down"')

---@class HoverController
---@field setup fun(cfg: HoverConfig, view: HoverView, provider: HoverProvider)
---@field enable fun()
---@field disable fun()
---@field set_provider fun(fn: HoverProvider)
---@field show fun()

---@class HoverConfig
---@field enabled boolean
---@field timing HoverTimingConfig
---@field ui HoverUIConfig
---@field behavior HoverBehaviorConfig
---@field provider HoverProvider|nil

---@class HoverModule
---@field setup fun(opts?: HoverConfig)
---@field enable fun()
---@field disable fun()
---@field set_provider fun(fn: HoverProvider)
---@field show fun()
---@field hide fun()
---@field get_config fun(): HoverConfig

---@type HoverModule
local M = {}

--- 默认配置
---@type HoverConfig
local default_config = {
  -- 基础开关
  enabled = true,

  -- 时序配置
  timing = {
    hover_delay = 500,        -- 鼠标停留触发延迟（ms）
    close_delay = 300,        -- 鼠标移开后延迟关闭时间（ms）
    min_show_time = 0,        -- 最小显示时长（ms）
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
---@type HoverConfig
local config = default_config
---@type HoverController|nil
local controller = nil
---@type HoverView|nil
local view = nil
---@type HoverProvider|nil
local provider = nil

---设置插件配置
---@param opts HoverConfig|nil 配置选项
function M.setup(opts)
  opts = opts or {}

  -- 合并配置
  config = vim.tbl_deep_extend("force", default_config, opts)

  -- 合并嵌套配置
  if opts.timing then
    config.timing = vim.tbl_deep_extend("force", default_config.timing, opts.timing)
  end
  if opts.ui then
    config.ui = vim.tbl_deep_extend("force", default_config.ui, opts.ui)
  end
  if opts.behavior then
    config.behavior = vim.tbl_deep_extend("force", default_config.behavior, opts.behavior)
  end

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
