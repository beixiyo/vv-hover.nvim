-- ================================
-- vv-hover.nvim - Controller 模块
-- ================================
-- 单一职责：处理鼠标事件、定时器、状态管理
-- 不处理内容获取或 UI 渲染

---@class VVHover.Controller
---@field setup fun(cfg: VVHover.Config, view: VVHover.View, provider: VVHover.Provider)
---@field enable fun()
---@field disable fun()
---@field is_enabled fun(): boolean
---@field set_provider fun(fn: VVHover.Provider)
---@field show fun()
---@field hide fun()
---@field _get_mouse_pos fun(): VVHover.MousePos|nil
---@field _make_mouse_key fun(pos: VVHover.MousePos): string
---@field _on_mouse_move fun()
---@field _on_scroll fun(direction: 'up'|'down')
---@field _start_hover_timer fun(key: string)
---@field _trigger_hover fun(key: string)
---@field _show_hover_result fun(result: VVHover.ProviderResult|nil, key: string, request: vv-utils.async.Request, winid: integer, bufnr: integer)
---@field _schedule_close fun()
---@field _cleanup_timers fun()
local M = {}
local request_scope = require('vv-utils.async').scope({ cancel_previous = true })

---@type VVHover.Config|{}
local config = {}
---@type VVHover.View|nil
local view = nil
---@type VVHover.Provider|nil
local provider = nil

-- 内部状态
local enabled = false
local hover_timer = nil
local close_timer = nil
local last_mouse_key = nil
local active_hover_key = nil
---@type table|nil
local active_hover_owner = nil
local lifecycle_generation = 0

-- 保存原始状态（用于 disable 时恢复）
local saved_mousemoveevent = nil
local owned_mousemoveevent = nil
local hover_augroup = nil
local Mappings = require('vv-hover.mappings')

---鼠标是否落在行尾之后的空白区
---getmousepos 在文本之后返回 column = #line + 1；若放行，provider 会把它夹到行尾，
---LSP 对行尾位置返回最后一个 token 的 hover，表现为右侧空白处也弹出浮窗
---@param pos VVHover.MousePos
---@return boolean
local function is_past_text(pos)
  if not vim.api.nvim_win_is_valid(pos.winid) then return false end
  local buf = vim.api.nvim_win_get_buf(pos.winid)
  local line = vim.api.nvim_buf_get_lines(buf, pos.line - 1, pos.line, false)[1]
  return line ~= nil and pos.column > #line
end

---@param pos VVHover.MousePos|nil
---@return boolean
local function is_source_mouse_pos(pos)
  return pos ~= nil and pos.winid ~= 0 and pos.line ~= 0 and pos.column ~= 0 and not is_past_text(pos)
end

---@return VVHover.MousePos|nil
local function get_raw_mouse_pos()
  local ok, pos = pcall(vim.fn.getmousepos)
  if not ok or not pos then
    return nil
  end
  return pos
end

---@param owner table|nil 传入时只关闭该所有者标识对应的 hover
---@return boolean closed
local function close_active_hover(owner)
  if owner and active_hover_owner ~= owner then
    return false
  end

  if view then
    view.close()
  end
  active_hover_key = nil
  active_hover_owner = nil
  return true
end

local function smooth_scroll_window(winid, direction)
  local ok, scroll = pcall(require, 'vv-utils.scroll')
  if ok and scroll and type(scroll.mouse) == 'function' and scroll.mouse(direction, winid) then
    return
  end

  vim.api.nvim_win_call(winid, function()
    if direction == "up" then
      vim.cmd("normal! 3\25") -- \25 is <C-y>
    else
      vim.cmd("normal! 3\5")  -- \5 is <C-e>
    end
  end)
end

---初始化 controller 模块
---@param cfg VVHover.Config 配置
---@param v VVHover.View view 模块
---@param p VVHover.Provider provider 函数
function M.setup(cfg, v, p)
  request_scope:cancel()
  config = cfg
  view = v
  provider = p
end

---启用插件
function M.enable()
  if enabled then
    return
  end

  enabled = true
  lifecycle_generation = lifecycle_generation + 1
  request_scope:invalidate()

  -- 保存并启用鼠标移动事件
  saved_mousemoveevent = vim.o.mousemoveevent
  vim.o.mousemoveevent = true
  owned_mousemoveevent = vim.o.mousemoveevent

  Mappings.install(M._on_mouse_move, M._on_scroll)

  -- 创建 augroup 并注册 autocmd
  hover_augroup = vim.api.nvim_create_augroup('VVHover', { clear = true })

  if config.behavior.close_on_insert then
    vim.api.nvim_create_autocmd("InsertEnter", {
      group = hover_augroup,
      callback = function()
        M.hide()
      end,
    })
  end
end

---禁用插件
function M.disable()
  if not enabled then
    return
  end

  enabled = false
  lifecycle_generation = lifecycle_generation + 1
  request_scope:cancel()

  -- 清理定时器
  M._cleanup_timers()

  -- 关闭浮窗
  close_active_hover()

  Mappings.restore()

  -- 恢复 mousemoveevent 原始值
  if saved_mousemoveevent ~= nil and vim.o.mousemoveevent == owned_mousemoveevent then
    vim.o.mousemoveevent = saved_mousemoveevent
  end
  saved_mousemoveevent = nil
  owned_mousemoveevent = nil

  -- 清理 augroup（移除所有 autocmd）
  if hover_augroup then
    vim.api.nvim_create_augroup('VVHover', { clear = true })
    hover_augroup = nil
  end

  -- 重置状态
  last_mouse_key = nil
end

---查询当前是否已启用（真实状态的唯一来源）
---@return boolean
function M.is_enabled()
  return enabled
end

---设置自定义 provider
---@param fn VVHover.Provider provider 函数
function M.set_provider(fn)
  request_scope:cancel()
  provider = fn
end

---关闭 hover 并取消当前 provider 请求
function M.hide()
  request_scope:cancel()
  M._cleanup_timers()
  close_active_hover()
end

---手动显示 hover（基于当前鼠标位置）
function M.show()
  if not enabled then
    return
  end

  local pos = M._get_mouse_pos()
  if not pos then
    return
  end

  local key = M._make_mouse_key(pos)
  M._trigger_hover(key)
end

---获取鼠标位置
---@return table|nil
function M._get_mouse_pos()
  local pos = get_raw_mouse_pos()
  if not is_source_mouse_pos(pos) then
    return nil
  end

  return pos
end

---根据鼠标位置构建唯一 key
---@param pos table
---@return string
function M._make_mouse_key(pos)
  return string.format("%d:%d:%d", pos.winid, pos.line, pos.column)
end

---鼠标移动事件处理
function M._on_mouse_move()
  if not enabled then
    return
  end

  local pos = M._get_mouse_pos()
  if not pos then
    -- 鼠标从源码区移向浮窗时必然先经过边框，Neovim 此时给出 line/column = 0。
    -- _get_mouse_pos() 仍须维持“仅有效源码位置”的契约，因此仅在这里取原始位置
    -- 命中浮窗，避免 hover 在进入内容区前被关掉。
    local raw_pos = get_raw_mouse_pos()
    if view and view.is_open and view.is_open() and view.is_mouse_inside and view.is_mouse_inside(raw_pos) then
      if close_timer then
        close_timer:stop()
        close_timer:close()
        close_timer = nil
      end
      return
    end

    -- 仍在源码窗口、只是落在行尾之后的空白：不触发新 hover，旧 hover 与移到别处
    -- 一样走 close_on_move 的延迟关闭，保留鼠标斜穿空白区移入浮窗的时间窗口
    if raw_pos and raw_pos.winid ~= 0 and raw_pos.line ~= 0 and raw_pos.column ~= 0 then
      request_scope:cancel()
      if hover_timer then
        hover_timer:stop()
        hover_timer:close()
        hover_timer = nil
      end
      last_mouse_key = nil
      if active_hover_key and config.behavior.close_on_move then
        M._schedule_close()
      end
      return
    end

    -- 鼠标离开窗口：清理定时器并关闭 hover
    request_scope:cancel()
    M._cleanup_timers()
    last_mouse_key = nil
    close_active_hover()
    return
  end

  if view and view.is_open and view.is_open() and view.is_mouse_inside and view.is_mouse_inside(pos) then
    if close_timer then
      close_timer:stop()
      close_timer:close()
      close_timer = nil
    end
    return
  end

  local key = M._make_mouse_key(pos)

  -- 鼠标从当前 hover 位置移开时
  if active_hover_key and key ~= active_hover_key then
    -- 如果有延迟关闭，则启动定时器
    if config.behavior.close_on_move then
      M._schedule_close()
    end
  end

  -- 位置未变化，不需要重置定时器（防抖）
  if last_mouse_key == key then
    return
  end

  request_scope:cancel()
  last_mouse_key = key

  -- 启动 hover 定时器
  M._start_hover_timer(key)
end

---滚轮事件处理
---@param direction "up"|"down"
function M._on_scroll(direction)
  if not enabled then
    return
  end

  -- 滚轮只关心鼠标落在哪个窗口，必须用原始位置：_get_mouse_pos() 是 hover 的“有效源码位置”过滤，
  -- 行尾之后的空白、空行、浮窗边框都会被它丢弃，从而退回到焦点窗口，滚错窗口
  local pos = get_raw_mouse_pos()
  if view and view.is_open() and view.is_mouse_inside(pos) then
    view.scroll(direction)
    return
  end

  -- 如果鼠标在某个有效的窗口内，就在该窗口内执行滚动（模拟原生鼠标滚动悬停窗口的行为）
  if pos and pos.winid and vim.api.nvim_win_is_valid(pos.winid) then
    smooth_scroll_window(pos.winid, direction)
  else
    smooth_scroll_window(vim.api.nvim_get_current_win(), direction)
  end
end

---启动 hover 定时器
---@param key string 鼠标位置 key
function M._start_hover_timer(key)
  if not enabled then
    return
  end

  -- 清理旧定时器
  if hover_timer then
    ---@cast hover_timer -nil
    hover_timer:stop()
    hover_timer:close()
    hover_timer = nil
  end

  -- 创建新定时器（捕获本地句柄 t，回调中只操作 t，避免误关已被替换的新定时器）
  local t = assert(vim.uv.new_timer())
  ---@cast t -nil
  local current_generation = lifecycle_generation
  hover_timer = t
  t:start(config.timing.hover_delay, 0, vim.schedule_wrap(function()
    if not enabled or current_generation ~= lifecycle_generation then
      if not t:is_closing() then
        t:close()
      end
      if hover_timer == t then
        hover_timer = nil
      end
      return
    end

    -- 检查鼠标位置是否仍然匹配
    local pos = M._get_mouse_pos()
    if pos then
      local current_key = M._make_mouse_key(pos)
      if current_key == key then
        M._trigger_hover(key)
      end
    end

    -- 只清理自己这个定时器句柄
    if not t:is_closing() then
      t:close()
    end
    -- 仅当模块变量仍指向自己时才置空，避免误清新定时器
    if hover_timer == t then
      hover_timer = nil
    end
  end))
end

---触发 hover 显示
---@param key string 鼠标位置 key
function M._trigger_hover(key)
  if not enabled then
    return
  end

  local pos = M._get_mouse_pos()
  if not pos then
    return
  end

  local winid = pos.winid
  local bufnr = vim.api.nvim_win_get_buf(winid)

  -- buffer 校验
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  if config.behavior.only_normal_buf and vim.bo[bufnr].buftype ~= "" then
    return
  end

  -- 构建上下文
  local line_text = vim.api.nvim_buf_get_lines(bufnr, pos.line - 1, pos.line, true)[1] or ""
  local ctx = {
    bufnr = bufnr,
    winid = winid,
    row = pos.line,
    col = pos.column,
    line_text = line_text,
    mouse_pos = pos,
    lsp_clients = vim.lsp.get_clients({ bufnr = bufnr }),
  }

  if not provider then
    return
  end

  local request = request_scope:begin()

  -- 调用 provider 获取内容
  -- provider 可能是：
  -- 1. 自定义函数：function(ctx) -> result | nil（同步）
  -- 2. 异步 provider：function(ctx, callback) -> true, cancel?

  -- 定义回调函数
  local callback = function(result)
    -- 再次检查鼠标位置是否仍然匹配
    local current_pos = M._get_mouse_pos()
    if not current_pos then
      request:finish()
      return
    end
    local current_key = M._make_mouse_key(current_pos)
    if current_key ~= key or current_pos.winid ~= winid then
      request:finish()
      return
    end
    if not vim.api.nvim_win_is_valid(winid) or vim.api.nvim_win_get_buf(winid) ~= bufnr then
      request:finish()
      return
    end

    M._show_hover_result(result, key, request, current_pos.winid, bufnr)
  end

  -- 调用 provider：
  -- - 异步 provider：接受 (ctx, callback)，返回 true，结果通过 callback 返回
  -- - 同步 provider：接受 (ctx) 或 (ctx, callback)，不返回 true，直接返回结果
  -- 统一传入 (ctx, callback)，根据返回值判断类型，避免重复调用
  local result, cancel = provider(ctx, callback)

  if result == true then
    if type(cancel) == 'function' then request:set_cancel(cancel) end
    -- 异步 provider 已发起请求，等待 callback 回调
    return
  end

  -- 同步 provider：直接使用第一次调用的返回值
  if result and result.lines then
    M._show_hover_result(result, key, request, winid, bufnr)
  else
    request:finish()
  end
end

---显示 hover 结果
---@param result table|nil hover 结果 { lines = string[], filetype = string }
---@param key string 鼠标位置 key
---@param request vv-utils.async.Request 请求 scope token
---@param winid number|nil 鼠标所悬停的窗口 ID（传给 view.open 以正确绑定记账 buffer）
---@param bufnr integer 发起请求时的 buffer
function M._show_hover_result(result, key, request, winid, bufnr)
  if not request:finish() or not enabled then return end
  if not winid or not vim.api.nvim_win_is_valid(winid) then return end
  if vim.api.nvim_win_get_buf(winid) ~= bufnr then return end

  if not result or not result.lines or vim.tbl_isempty(result.lines) then
    return
  end

  -- 关闭旧浮窗
  close_active_hover()

  -- 打开新浮窗
  if not view then
    return
  end
  local bufnr_f, winid_f = view.open(result.lines, result.filetype, winid)
  if bufnr_f and winid_f then
    active_hover_key = key
    active_hover_owner = {}
  end
end

---延迟关闭浮窗
function M._schedule_close()
  -- 清理旧定时器
  if close_timer then
    ---@cast close_timer -nil
    close_timer:stop()
    close_timer:close()
    close_timer = nil
  end

  local closing_key = active_hover_key
  local closing_owner = active_hover_owner
  if not closing_key or not closing_owner then
    return
  end

  -- 如果延迟时间为 0，立即关闭
  if config.timing.close_delay == 0 then
    close_active_hover(closing_owner)
    return
  end

  -- 创建延迟关闭定时器（捕获本地句柄 t，回调中只操作 t）
  local t = assert(vim.uv.new_timer())
  ---@cast t -nil
  local current_generation = lifecycle_generation
  close_timer = t
  t:start(config.timing.close_delay, 0, vim.schedule_wrap(function()
    if not enabled or current_generation ~= lifecycle_generation then
      if not t:is_closing() then
        t:close()
      end
      if close_timer == t then
        close_timer = nil
      end
      return
    end

    -- 旧 hover 已被后继替换时，这个 timer 不得关闭后继 UI
    if active_hover_owner ~= closing_owner then
      if not t:is_closing() then
        t:close()
      end
      if close_timer == t then
        close_timer = nil
      end
      return
    end

    -- 检查鼠标是否已经移回旧 hover 的位置。_get_mouse_pos() 保留可替换的
    -- 有效源码位置测试入口；只有它返回 nil 时才额外判断浮窗边框等原始坐标。
    local pos = M._get_mouse_pos()
    if not pos then
      local raw_pos = get_raw_mouse_pos()
      if view and view.is_open and view.is_open() and view.is_mouse_inside and view.is_mouse_inside(raw_pos) then
        -- 即使浮窗的 MouseMove 映射未先执行，到期时仍以实际命中区域为准。
        if not t:is_closing() then
          t:close()
        end
        if close_timer == t then
          close_timer = nil
        end
        return
      end
    elseif view and view.is_open and view.is_open() and view.is_mouse_inside and view.is_mouse_inside(pos) then
      if not t:is_closing() then
        t:close()
      end
      if close_timer == t then
        close_timer = nil
      end
      return
    end

    if pos then
      local key = M._make_mouse_key(pos)
      if key == closing_key then
        -- 鼠标移回了，取消关闭：只清理自己这个句柄
        if not t:is_closing() then
          t:close()
        end
        if close_timer == t then
          close_timer = nil
        end
        return
      end
    end

    -- close timer 只拥有创建时已显示的 hover；新的 provider request
    -- 由鼠标位置和生命周期事件管理，不能在这里取消共享 scope
    close_active_hover(closing_owner)

    -- 只清理自己这个定时器句柄
    if not t:is_closing() then
      t:close()
    end
    if close_timer == t then
      close_timer = nil
    end
  end))
end

---清理所有定时器
function M._cleanup_timers()
  if hover_timer then
    hover_timer:stop()
    hover_timer:close()
    hover_timer = nil
  end

  if close_timer then
    close_timer:stop()
    close_timer:close()
    close_timer = nil
  end
end

return M
