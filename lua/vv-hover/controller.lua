-- ================================
-- vv-hover.nvim - Controller 模块
-- ================================
-- 单一职责：处理鼠标事件、定时器、状态管理
-- 不处理内容获取或 UI 渲染

local M = {}

---@type VVHoverConfig|{}
local config = {}
---@type VVHoverView|nil
local view = nil
---@type VVHoverProvider|nil
local provider = nil

-- 内部状态
local enabled = false
local hover_timer = nil
local close_timer = nil
local last_mouse_key = nil
local active_hover_key = nil
local request_token = 0 -- 用于解决竞态条件

-- 保存原始状态（用于 disable 时恢复）
local saved_mousemoveevent = nil
local saved_scroll_up_map = nil
local saved_scroll_down_map = nil
local hover_augroup = nil

-- 鼠标移动事件映射键
local MOUSE_MOVE_KEY = "<MouseMove>"

---初始化 controller 模块
---@param cfg table 配置
---@param v table view 模块
---@param p function provider 函数
function M.setup(cfg, v, p)
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

  -- 保存并启用鼠标移动事件
  saved_mousemoveevent = vim.o.mousemoveevent
  vim.o.mousemoveevent = true

  -- 注册鼠标移动事件
  pcall(vim.keymap.set, "n", MOUSE_MOVE_KEY, M._on_mouse_move, {
    desc = "鼠标悬停自动显示 Hover",
  })

  -- 保存原始滚轮映射（用于 disable 时恢复）
  saved_scroll_up_map = vim.fn.maparg("<ScrollWheelUp>", "n", false, true)
  saved_scroll_down_map = vim.fn.maparg("<ScrollWheelDown>", "n", false, true)

  -- 注册滚轮事件（用于滚动浮窗）
  pcall(vim.keymap.set, "n", "<ScrollWheelUp>", function()
    M._on_scroll("up")
  end, { desc = "向上滚动 Hover 浮窗" })
  pcall(vim.keymap.set, "n", "<ScrollWheelDown>", function()
    M._on_scroll("down")
  end, { desc = "向下滚动 Hover 浮窗" })

  -- 创建 augroup 并注册 autocmd
  hover_augroup = vim.api.nvim_create_augroup('VVHover', { clear = true })

  if config.behavior.close_on_insert then
    vim.api.nvim_create_autocmd("InsertEnter", {
      group = hover_augroup,
      callback = function()
        M._cleanup_timers()
        if view then
          view.close()
        end
      end,
    })
  end
end

---恢复之前保存的按键映射
---@param map table|nil maparg() 返回的映射信息
local function restore_mapping(map)
  if not map or vim.tbl_isempty(map) then
    return
  end
  -- maparg(dict=true) 返回的 lhs 字段即为原始按键
  local mode = map.mode or 'n'
  local lhs = map.lhs
  local rhs = map.rhs or map.callback
  if not lhs or (not rhs and not map.callback) then
    return
  end
  vim.keymap.set(mode, lhs, rhs, {
    silent = map.silent == 1,
    noremap = map.noremap == 1,
    expr = map.expr == 1,
    nowait = map.nowait == 1,
    desc = map.desc,
    buffer = (map.buffer and map.buffer ~= 0) and map.buffer or nil,
  })
end

---禁用插件
function M.disable()
  if not enabled then
    return
  end

  enabled = false

  -- 清理定时器
  M._cleanup_timers()

  -- 关闭浮窗
  if view then
    view.close()
  end

  -- 移除鼠标移动事件映射
  pcall(vim.keymap.del, "n", MOUSE_MOVE_KEY)

  -- 恢复原始滚轮映射（而非直接删除）
  pcall(vim.keymap.del, "n", "<ScrollWheelUp>")
  pcall(vim.keymap.del, "n", "<ScrollWheelDown>")
  restore_mapping(saved_scroll_up_map)
  restore_mapping(saved_scroll_down_map)
  saved_scroll_up_map = nil
  saved_scroll_down_map = nil

  -- 恢复 mousemoveevent 原始值
  if saved_mousemoveevent ~= nil then
    vim.o.mousemoveevent = saved_mousemoveevent
    saved_mousemoveevent = nil
  end

  -- 清理 augroup（移除所有 autocmd）
  if hover_augroup then
    vim.api.nvim_create_augroup('VVHover', { clear = true })
    hover_augroup = nil
  end

  -- 重置状态
  last_mouse_key = nil
  active_hover_key = nil
end

---查询当前是否已启用（真实状态的唯一来源）
---@return boolean
function M.is_enabled()
  return enabled
end

---设置自定义 provider
---@param fn function provider 函数
function M.set_provider(fn)
  provider = fn
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
  local ok, pos = pcall(vim.fn.getmousepos)
  if not ok or not pos then
    return nil
  end
  -- 鼠标在状态栏 / 垂直分隔线上时，getmousepos 会返回 winid != 0 但 line == 0
  -- 或 column == 0，此时构建出的 LSP 位置会是非法的 line = -1，需一并过滤。
  if pos.winid == 0 or pos.line == 0 or pos.column == 0 then
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
    -- 鼠标离开窗口：清理定时器并关闭 hover
    M._cleanup_timers()
    last_mouse_key = nil
    if view then
      view.close()
    end
    return
  end
  
  local key = M._make_mouse_key(pos)
  
  -- 鼠标进入 hover 浮窗 UI 时，不要关闭/不要重触发
  if view and view.is_open and view.is_open() and view.is_mouse_inside and view.is_mouse_inside(pos) then
    -- 鼠标在浮窗内，取消关闭定时器（如果存在）
    if close_timer then
      close_timer:stop()
      close_timer:close()
      close_timer = nil
    end
    -- 不触发关闭逻辑，直接返回
    return
  end
  
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

  local pos = M._get_mouse_pos()
  if view and view.is_open() and view.is_mouse_inside(pos) then
    view.scroll(direction)
    return
  end

  -- 如果鼠标在某个有效的窗口内，就在该窗口内执行滚动（模拟原生鼠标滚动悬停窗口的行为）
  if pos and pos.winid and vim.api.nvim_win_is_valid(pos.winid) then
    vim.api.nvim_win_call(pos.winid, function()
      if direction == "up" then
        vim.cmd("normal! 3\25") -- \25 is <C-y>
      else
        vim.cmd("normal! 3\5")  -- \5 is <C-e>
      end
    end)
  else
    -- 兜底：在当前焦点窗口滚动
    local key = direction == "up" and "3<C-Y>" or "3<C-E>"
    local esc_key = vim.api.nvim_replace_termcodes(key, true, false, true)
    vim.api.nvim_feedkeys(esc_key, "n", false)
  end
end

---启动 hover 定时器
---@param key string 鼠标位置 key
function M._start_hover_timer(key)
  -- 清理旧定时器
  if hover_timer then
    hover_timer:stop()
    hover_timer:close()
    hover_timer = nil
  end
  
  -- 创建新定时器（捕获本地句柄 t，回调中只操作 t，避免误关已被替换的新定时器）
  local t = vim.uv.new_timer()
  hover_timer = t
  t:start(config.timing.hover_delay, 0, vim.schedule_wrap(function()
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
  
  -- 生成请求 token（用于解决竞态条件）
  request_token = request_token + 1
  local current_token = request_token
  
  if not provider then
    return
  end
  
  -- 调用 provider 获取内容
  -- provider 可能是：
  -- 1. 自定义函数：function(ctx) -> result | nil（同步）
  -- 2. LSP provider：function(ctx, callback) -> boolean（异步，返回是否成功发起请求）
  
  -- 定义回调函数
  local callback = function(result)
    -- 检查 token 是否仍然有效（解决竞态条件）
    if current_token ~= request_token then
      return
    end
    
    -- 再次检查鼠标位置是否仍然匹配
    local current_pos = M._get_mouse_pos()
    if not current_pos then
      return
    end
    local current_key = M._make_mouse_key(current_pos)
    if current_key ~= key then
      return
    end

    M._show_hover_result(result, key, current_token, current_pos.winid)
  end
  
  -- 调用 provider：
  -- - 异步 provider：接受 (ctx, callback)，返回 true，结果通过 callback 返回
  -- - 同步 provider：接受 (ctx) 或 (ctx, callback)，不返回 true，直接返回结果
  -- 统一传入 (ctx, callback)，根据返回值判断类型，避免重复调用
  local result = provider(ctx, callback)

  if result == true then
    -- 异步 provider 已发起请求，等待 callback 回调
    return
  end

  -- 同步 provider：直接使用第一次调用的返回值
  if result and result.lines then
    M._show_hover_result(result, key, current_token, winid)
  end
end

---显示 hover 结果
---@param result table|nil hover 结果 { lines = string[], filetype = string }
---@param key string 鼠标位置 key
---@param token number 请求 token
---@param winid number|nil 鼠标所悬停的窗口 ID（传给 view.open 以正确绑定记账 buffer）
function M._show_hover_result(result, key, token, winid)
  -- 再次检查 token（双重保险）
  if token ~= request_token then
    return
  end

  if not result or not result.lines or vim.tbl_isempty(result.lines) then
    return
  end

  -- 关闭旧浮窗
  if view then
    view.close()
  end

  -- 打开新浮窗
  if not view then
    return
  end
  local bufnr_f, winid_f = view.open(result.lines, result.filetype, winid)
  if bufnr_f and winid_f then
    active_hover_key = key
  end
end

---延迟关闭浮窗
function M._schedule_close()
  -- 清理旧定时器
  if close_timer then
    close_timer:stop()
    close_timer:close()
    close_timer = nil
  end
  
  -- 如果延迟时间为 0，立即关闭
  if config.timing.close_delay == 0 then
    if view then
      view.close()
    end
    active_hover_key = nil
    return
  end
  
  -- 创建延迟关闭定时器（捕获本地句柄 t，回调中只操作 t）
  local t = vim.uv.new_timer()
  close_timer = t
  t:start(config.timing.close_delay, 0, vim.schedule_wrap(function()
    -- 检查鼠标是否已经移回
    local pos = M._get_mouse_pos()
    if pos then
      local key = M._make_mouse_key(pos)
      if key == active_hover_key then
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

    if view then
      view.close()
    end
    active_hover_key = nil

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
