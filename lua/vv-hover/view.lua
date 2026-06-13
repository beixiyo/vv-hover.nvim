-- ================================
-- vv-hover.nvim - View 模块
-- ================================
-- 单一职责：负责浮窗的打开和关闭
-- 不处理事件、定时器或内容获取

local M = {}

local config = {}
local current_win = nil
local current_bufnr = nil

---初始化 view 模块
---@param cfg table 配置
function M.setup(cfg)
  config = cfg
end

---打开浮窗显示内容
---@param lines string[] 要显示的行内容
---@param filetype string|nil 文件类型（默认 "markdown"）
---@param winid number|nil 鼠标所悬停的窗口 ID（用于让 open_floating_preview 的记账绑定到被悬停的 buffer 而非焦点 buffer）
---@return number|nil bufnr 创建的 buffer ID
---@return number|nil winid 创建的窗口 ID
function M.open(lines, filetype, winid)
  if not lines or vim.tbl_isempty(lines) then
    return nil, nil
  end

  filetype = filetype or "markdown"

  -- 关闭旧浮窗
  M.close()

  -- 裁剪空行
  lines = M._trim_empty_lines(lines)
  if vim.tbl_isempty(lines) then
    return nil, nil
  end

  -- 构建浮窗选项
  -- close_events 置空：本插件通过 current_win + 自有定时器管理生命周期，
  -- 不依赖 open_floating_preview 默认的 {CursorMoved,...} 关闭 autocmd。
  -- 否则鼠标驱动的浮窗会被焦点窗口里无关的 CursorMoved 误关。
  local opts = {
    border = config.ui.border,
    focusable = config.ui.focusable,
    max_width = config.ui.max_width,
    max_height = config.ui.max_height,
    relative = config.ui.relative,
    zindex = config.ui.zindex,
    close_events = {},
  }

  -- 打开浮窗
  -- open_floating_preview 内部用 nvim_get_current_buf() 决定 b:lsp_floating_preview
  -- 复用变量与各类记账。本插件是鼠标驱动的，被悬停的窗口未必是焦点窗口，
  -- 因此在被悬停的窗口上下文里调用，让记账落到正确的 buffer。
  local util = vim.lsp.util
  local bufnr_f, winid_f
  if winid and vim.api.nvim_win_is_valid(winid) then
    vim.api.nvim_win_call(winid, function()
      bufnr_f, winid_f = util.open_floating_preview(lines, filetype, opts)
    end)
  else
    bufnr_f, winid_f = util.open_floating_preview(lines, filetype, opts)
  end

  -- 本插件不使用 open_floating_preview 的复用机制（自管 current_win），
  -- 清掉它在源 buffer 上写下的 b:lsp_floating_preview，避免误触该 buffer 的 K 浮窗记账。
  local src_winid = (winid and vim.api.nvim_win_is_valid(winid)) and winid or vim.api.nvim_get_current_win()
  local src_bufnr = vim.api.nvim_win_get_buf(src_winid)
  if vim.api.nvim_buf_is_valid(src_bufnr) then
    pcall(vim.api.nvim_buf_del_var, src_bufnr, "lsp_floating_preview")
  end

  current_bufnr = bufnr_f
  current_win = winid_f

  return bufnr_f, winid_f
end

---关闭浮窗
function M.close()
  if current_win and vim.api.nvim_win_is_valid(current_win) then
    pcall(vim.api.nvim_win_close, current_win, true)
  end
  if current_bufnr and vim.api.nvim_buf_is_valid(current_bufnr) then
    pcall(vim.api.nvim_buf_delete, current_bufnr, { force = true })
  end
  current_win = nil
  current_bufnr = nil
end

---检查浮窗是否打开
---@return boolean
function M.is_open()
  return current_win ~= nil and vim.api.nvim_win_is_valid(current_win)
end

---获取当前浮窗信息
---@return number|nil winid
---@return number|nil bufnr
function M.get_current()
  return current_win, current_bufnr
end

---检查鼠标是否在浮窗内
---@param mouse_pos table|nil 鼠标位置 { winid, line, column, screenrow, screencol }
---@return boolean
function M.is_mouse_inside(mouse_pos)
  if not mouse_pos or not current_win or not vim.api.nvim_win_is_valid(current_win) then
    return false
  end

  -- 优先通过 winid 匹配（最准确，且 getmousepos 会返回浮窗 winid）
  if mouse_pos.winid == current_win then
    return true
  end
  
  -- 也要检查是否在边框上。getmousepos().winid 有时可能因为 border 设定不返回浮窗 winid
  local wininfo = vim.fn.getwininfo(current_win)
  local info = (wininfo and wininfo[1]) or nil
  if not info then
    return false
  end

  local row = mouse_pos.screenrow or 0
  local col = mouse_pos.screencol or 0
  if row <= 0 or col <= 0 then
    return false
  end

  -- getwininfo() 的 winrow/wincol 是内容区域左上角坐标（1-based）
  -- 如果有边框，我们需要向外扩展判断区域
  local has_border = config.ui.border ~= "none"
  local top = info.winrow - (has_border and 1 or 0)
  local left = info.wincol - (has_border and 1 or 0)
  local bottom = info.winrow + info.height - 1 + (has_border and 1 or 0)
  local right = info.wincol + info.width - 1 + (has_border and 1 or 0)

  return row >= top and row <= bottom and col >= left and col <= right
end

---滚动浮窗内容
---@param direction "up"|"down" 滚动方向
function M.scroll(direction)
  if not current_win or not vim.api.nvim_win_is_valid(current_win) then
    return
  end
  -- 直接用 <C-y>/<C-e>，交由 Neovim 处理 wrap 行与边界，避免手动算 topline 时
  -- 因 scrolloff 反弹或 wrap 行数不匹配导致的"抖动"
  vim.api.nvim_win_call(current_win, function()
    local keys = direction == "up" and "3\25" or "3\5"
    vim.cmd("normal! " .. keys)
  end)
end

---裁剪首尾空行
---@param lines string[]
---@return string[]
function M._trim_empty_lines(lines)
  if not lines or #lines == 0 then
    return {}
  end
  
  local start = 1
  for i = 1, #lines do
    if lines[i] ~= nil and #lines[i] > 0 then
      start = i
      break
    end
  end
  
  local finish = #lines
  for i = #lines, 1, -1 do
    if lines[i] ~= nil and #lines[i] > 0 then
      finish = i
      break
    end
  end
  
  -- 如果全是空行，返回空数组
  if start > finish then
    return {}
  end
  
  return vim.list_extend({}, lines, start, finish)
end

return M
