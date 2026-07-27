-- Owns process-global mouse mappings while vv-hover is enabled.

local M = {}
local saved = {}
local owned = {}
local installed = false
local focus = { key = nil, saved = nil, owned = nil }

local keys = { '<MouseMove>', '<ScrollWheelUp>', '<ScrollWheelDown>' }

local function get_global_map(key)
  for _, map in ipairs(vim.api.nvim_get_keymap('n')) do
    if map.lhs == key then return map end
  end
end

local function restore(map)
  if not map then return end
  vim.keymap.set(map.mode or 'n', map.lhs, map.callback or map.rhs, {
    silent = map.silent == 1,
    noremap = map.noremap == 1,
    expr = map.expr == 1,
    nowait = map.nowait == 1,
    desc = map.desc,
  })
end

local function is_owned(key)
  local current = get_global_map(key)
  local installed_map = owned[key]
  if not installed_map or not current then return false end

  return current.callback == installed_map.callback
    and current.rhs == installed_map.rhs
    and current.desc == installed_map.desc
end

function M.install(on_move, on_scroll)
  if installed then return end

  for _, key in ipairs(keys) do
    saved[key] = get_global_map(key)
  end

  vim.keymap.set('n', '<MouseMove>', on_move, { desc = 'Show hover' })
  vim.keymap.set('n', '<ScrollWheelUp>', function() on_scroll('up') end, { desc = 'Scroll hover up' })
  vim.keymap.set('n', '<ScrollWheelDown>', function() on_scroll('down') end, { desc = 'Scroll hover down' })
  for _, key in ipairs(keys) do owned[key] = get_global_map(key) end
  installed = true
end

function M.restore()
  if not installed then return end

  for _, key in ipairs(keys) do
    if is_owned(key) then
      pcall(vim.keymap.del, 'n', key)
      restore(saved[key])
    end
    saved[key] = nil
    owned[key] = nil
  end
  installed = false
  M.restore_focus()
end

---Own the optional focus mapping with the same capture/restore rules as mouse maps.
---@param key string|false
---@param callback fun()
function M.configure_focus(key, callback)
  M.restore_focus()
  if type(key) ~= 'string' or key == '' then return end

  focus.key = key
  focus.saved = get_global_map(key)
  vim.keymap.set('n', key, callback, { desc = 'vv-hover: 聚焦悬停浮窗', silent = true })
  focus.owned = get_global_map(key)
end

function M.restore_focus()
  if not focus.key then return end
  local current = get_global_map(focus.key)
  if current and focus.owned
      and current.callback == focus.owned.callback
      and current.rhs == focus.owned.rhs
      and current.desc == focus.owned.desc
  then
    pcall(vim.keymap.del, 'n', focus.key)
    restore(focus.saved)
  end
  focus.key, focus.saved, focus.owned = nil, nil, nil
end

return M
