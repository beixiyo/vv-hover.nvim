-- Owns process-global mouse mappings while vv-hover is enabled.

local M = {}
local saved = {}
local owned = {}
local installed = false

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
end

return M
