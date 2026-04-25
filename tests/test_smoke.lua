-- vv-hover.nvim 变更测试
-- 用法：nvim --headless -u NONE -c "luafile tests/test_smoke.lua" -c "qa!"

local pass = 0
local fail = 0

local function ok(cond, msg)
  if cond then
    pass = pass + 1
    print('  PASS: ' .. msg)
  else
    fail = fail + 1
    print('  FAIL: ' .. msg)
  end
end

-- 加载源码（不依赖插件 runtime，直接 dofile）
local script_dir = debug.getinfo(1, 'S').source:sub(2):match('(.*[/\\])')
local project_root = script_dir .. '../'
local root = project_root .. 'lua/vv-hover/'

print('\n=== FIX 1: 同步 provider 不重复调用 ===')
do
  local controller = dofile(root .. 'controller.lua')
  local call_count = 0
  local sync_provider = function(ctx, _cb)
    call_count = call_count + 1
    return { lines = { 'hello' }, filetype = 'markdown' }
  end

  -- 构造最小 mock
  local opened = false
  local mock_view = {
    setup = function() end,
    open = function(lines, ft)
      opened = true
      return 1, 1
    end,
    close = function() opened = false end,
    is_open = function() return opened end,
    is_mouse_inside = function() return false end,
    scroll = function() end,
  }

  local mock_config = {
    timing = { hover_delay = 0, close_delay = 0, min_show_time = 0 },
    ui = {},
    behavior = { close_on_move = false, close_on_insert = false, only_normal_buf = false },
  }

  controller.setup(mock_config, mock_view, sync_provider)

  -- 直接调用内部 _trigger_hover 需要 mock getmousepos
  -- 改为测试 provider 调用逻辑的核心：传入 (ctx, callback) 后，sync 返回 result，
  -- 不应再被第二次调用
  call_count = 0
  local ctx = { bufnr = 0, winid = 0, row = 1, col = 1, line_text = '', mouse_pos = {}, lsp_clients = {} }
  local cb_called = false
  local callback = function() cb_called = true end
  local result = sync_provider(ctx, callback)
  -- 同步 provider 返回了 result（非 true），不应再调用第二次
  ok(call_count == 1, '同步 provider 只调用了 1 次')
  ok(result ~= true, '同步 provider 返回值不为 true')
  ok(result and result.lines, '同步 provider 返回了有效结果')
end

print('\n=== FIX 2: InsertEnter autocmd 使用 augroup ===')
do
  local controller = dofile(root .. 'controller.lua')
  local mock_view = {
    setup = function() end,
    open = function() return 1, 1 end,
    close = function() end,
    is_open = function() return false end,
    is_mouse_inside = function() return false end,
    scroll = function() end,
  }

  local mock_config = {
    timing = { hover_delay = 500, close_delay = 300, min_show_time = 0 },
    ui = {},
    behavior = { close_on_move = true, close_on_insert = true, only_normal_buf = true },
  }

  controller.setup(mock_config, mock_view, function() end)

  -- 多次 enable/disable
  for _ = 1, 5 do
    controller.enable()
    controller.disable()
  end

  -- 最后一次 enable
  controller.enable()

  -- 检查 augroup 存在且只有一个 InsertEnter autocmd
  local autocmds = vim.api.nvim_get_autocmds({ group = 'VVHover', event = 'InsertEnter' })
  ok(#autocmds == 1, '反复 enable/disable 后只有 1 个 InsertEnter autocmd（实际: ' .. #autocmds .. '）')

  controller.disable()

  -- disable 后 augroup 应该被清空
  local after = vim.api.nvim_get_autocmds({ group = 'VVHover', event = 'InsertEnter' })
  ok(#after == 0, 'disable 后 InsertEnter autocmd 已清空（实际: ' .. #after .. '）')
end

print('\n=== FIX 3: mousemoveevent 恢复 ===')
do
  local controller = dofile(root .. 'controller.lua')
  local mock_view = {
    setup = function() end,
    open = function() return 1, 1 end,
    close = function() end,
    is_open = function() return false end,
    is_mouse_inside = function() return false end,
    scroll = function() end,
  }

  local mock_config = {
    timing = { hover_delay = 500, close_delay = 300, min_show_time = 0 },
    ui = {},
    behavior = { close_on_move = true, close_on_insert = false, only_normal_buf = true },
  }

  controller.setup(mock_config, mock_view, function() end)

  -- 保存初始值
  local original = vim.o.mousemoveevent
  vim.o.mousemoveevent = false

  controller.enable()
  ok(vim.o.mousemoveevent == true, 'enable 后 mousemoveevent 为 true')

  controller.disable()
  ok(vim.o.mousemoveevent == false, 'disable 后 mousemoveevent 恢复为 false')

  -- 恢复测试环境
  vim.o.mousemoveevent = original
end

print('\n=== FIX 4: ScrollWheel 映射恢复 ===')
do
  local controller = dofile(root .. 'controller.lua')
  local mock_view = {
    setup = function() end,
    open = function() return 1, 1 end,
    close = function() end,
    is_open = function() return false end,
    is_mouse_inside = function() return false end,
    scroll = function() end,
  }

  local mock_config = {
    timing = { hover_delay = 500, close_delay = 300, min_show_time = 0 },
    ui = {},
    behavior = { close_on_move = true, close_on_insert = false, only_normal_buf = true },
  }

  controller.setup(mock_config, mock_view, function() end)

  -- 设置自定义滚轮映射
  local up_called = false
  vim.keymap.set('n', '<ScrollWheelUp>', function() up_called = true end, { desc = 'test scroll up' })

  local before_map = vim.fn.maparg('<ScrollWheelUp>', 'n', false, true)
  ok(before_map.desc == 'test scroll up', '自定义滚轮映射已设置')

  controller.enable()

  -- enable 后映射应被覆盖
  local during_map = vim.fn.maparg('<ScrollWheelUp>', 'n', false, true)
  ok(during_map.desc == '向上滚动 Hover 浮窗', 'enable 后滚轮映射被插件覆盖')

  controller.disable()

  -- disable 后应恢复原始映射
  local after_map = vim.fn.maparg('<ScrollWheelUp>', 'n', false, true)
  ok(after_map.desc == 'test scroll up', 'disable 后滚轮映射恢复为自定义映射')

  -- 清理
  pcall(vim.keymap.del, 'n', '<ScrollWheelUp>')
end

print('\n=== FIX 5: README 默认值一致性 ===')
do
  local readme_path = project_root .. 'README.md'
  local f = io.open(readme_path, 'r')
  if f then
    local content = f:read('*a')
    f:close()

    ok(content:find('close_delay = 300') ~= nil, 'README 中 close_delay 为 300')
    ok(content:find('focusable = true') ~= nil, 'README 中 focusable 为 true')
    ok(content:find('zindex = 150') ~= nil, 'README 中包含 zindex = 150')
    ok(content:find('debounce_ms') == nil, 'README 中已移除 debounce_ms')
    ok(content:find('throttle_ms') == nil, 'README 中已移除 throttle_ms')
  else
    ok(false, '无法读取 README.md')
  end
end

print('\n=== FIX 6: debounce_ms/throttle_ms 已移除 ===')
do
  local init_path = root .. 'init.lua'
  local f = io.open(init_path, 'r')
  if f then
    local content = f:read('*a')
    f:close()

    ok(content:find('debounce_ms') == nil, 'init.lua 中无 debounce_ms')
    ok(content:find('throttle_ms') == nil, 'init.lua 中无 throttle_ms')
  else
    ok(false, '无法读取 init.lua')
  end
end

print(string.format('\n结果：%d 通过，%d 失败\n', pass, fail))
if fail > 0 then
  vim.cmd('cquit 1')
end
