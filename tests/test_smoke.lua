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

-- -u NONE 下 runtimepath 被剥离，手动把本插件与 vv-utils 的 lua/ 接进 package.path
-- 以便 require('vv-hover...') 可用（镜像兄弟插件的写法）
local this = debug.getinfo(1, 'S').source:sub(2)
local plugin_root = vim.fn.fnamemodify(this, ':p:h:h')
local vendors = vim.fn.fnamemodify(plugin_root, ':h')
package.path = table.concat({
  plugin_root .. '/lua/?.lua',
  plugin_root .. '/lua/?/init.lua',
  vendors .. '/vv-utils.nvim/lua/?.lua',
  vendors .. '/vv-utils.nvim/lua/?/init.lua',
  package.path,
}, ';')

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
    timing = { hover_delay = 0, close_delay = 0 },
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
    timing = { hover_delay = 500, close_delay = 300 },
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
    timing = { hover_delay = 500, close_delay = 300 },
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
    timing = { hover_delay = 500, close_delay = 300 },
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

print('\n=== BUG #52: LSP hover 列 0-based 转换 ===')
do
  -- lsp.lua 不 require 兄弟模块，dofile 即可
  local lsp = dofile(root .. 'providers/lsp.lua')

  ok(type(lsp._build_position) == 'function', 'lsp._build_position 位置构建 seam 存在')

  -- getmousepos 列是 1-based 字节列；鼠标在第 1 个字符上 → col == 1 → 应得 character 0
  -- line_text 含多字节 © 以验证 UTF 编码换算路径
  local pos1 = lsp._build_position(
    { row = 2, col = 1, line_text = 'ab©d' },
    'utf-16'
  )
  ok(pos1.character == 0, '1-based col=1 映射为 0-based character 0（实际: ' .. tostring(pos1.character) .. '）')
  ok(pos1.line == 1, 'row=2 映射为 0-based line 1（实际: ' .. tostring(pos1.line) .. '）')

  -- 越界 / 0 值被 clamp 到 >= 0，不应报错也不应得到负数
  local pos0 = lsp._build_position({ row = 1, col = 0, line_text = 'abc' }, 'utf-16')
  ok(pos0.character == 0, 'col=0 被 clamp 为 character 0（实际: ' .. tostring(pos0.character) .. '）')

  -- 第 3 个字符（©，2 字节于 utf-8）：col=3（1-based 字节列指向 ©）→ 0-based 字节 2 → utf-16 字符 2
  local pos3 = lsp._build_position({ row = 1, col = 3, line_text = 'ab©d' }, 'utf-16')
  ok(pos3.character == 2, '1-based col=3 映射为 0-based character 2（实际: ' .. tostring(pos3.character) .. '）')
end

print('\n=== BUG #53: 定时器回调捕获本地句柄（无竞态）===')
do
  -- 源码级断言：两个定时器（hover/close）都必须捕获本地句柄 t，
  -- 且绝不能把 new_timer() 直接赋给 module 级变量（旧的竞态写法）。
  local f = io.open(root .. 'controller.lua', 'r')
  local content = f and f:read('*a') or ''
  if f then f:close() end

  -- 统计 `local t = vim.uv.new_timer()` 出现次数（hover + close 各一次 → 2）
  local local_handles = 0
  for _ in content:gmatch('local t = vim%.uv%.new_timer%(%)') do
    local_handles = local_handles + 1
  end
  ok(local_handles == 2,
    '两个定时器均捕获本地句柄 local t = vim.uv.new_timer()（实际: ' .. local_handles .. '）')

  -- 旧的竞态写法（new_timer() 直接赋给 module 变量）必须彻底消失
  ok(content:find('hover_timer = vim%.uv%.new_timer%(%)') == nil,
    'hover_timer 不再直接赋值 new_timer()（旧竞态写法已移除）')
  ok(content:find('close_timer = vim%.uv%.new_timer%(%)') == nil,
    'close_timer 不再直接赋值 new_timer()（旧竞态写法已移除）')

  ok(content:find('if hover_timer == t then') ~= nil,
    'hover_timer 仅在仍 === t 时置空（避免误清新定时器）')
  ok(content:find('if close_timer == t then') ~= nil,
    'close_timer 仅在仍 === t 时置空')
end

print('\n=== BUG #54: toggle 以 controller 真实状态为准 ===')
do
  package.loaded['vv-hover'] = nil
  package.loaded['vv-hover.controller'] = nil
  package.loaded['vv-hover.view'] = nil
  package.loaded['vv-hover.providers.lsp'] = nil

  local hover = require('vv-hover')
  local controller = require('vv-hover.controller')

  hover.setup({ enabled = true })
  ok(controller.is_enabled() == true, 'setup(enabled=true) 后 controller 已启用')

  hover.disable()
  ok(controller.is_enabled() == false, 'disable 后 controller 已禁用')

  -- 关键：disable 之后 toggle 必须重新 ENABLE（修复前 config.enabled 漂移会导致此处为 no-op）
  hover.toggle()
  ok(controller.is_enabled() == true, 'disable 后 toggle 应重新启用 controller')

  -- 清理：还原状态
  hover.disable()
  package.loaded['vv-hover'] = nil
  package.loaded['vv-hover.controller'] = nil
  package.loaded['vv-hover.view'] = nil
  package.loaded['vv-hover.providers.lsp'] = nil
end

print('\n=== BUG #55: _get_mouse_pos 过滤状态栏/分隔线命中 ===')
do
  local controller = dofile(root .. 'controller.lua')

  local saved = vim.fn.getmousepos
  -- 模拟状态栏命中：winid != 0 但 line == 0
  vim.fn.getmousepos = function()
    return { winid = 5, line = 0, column = 0, screenrow = 1, screencol = 1 }
  end
  ok(controller._get_mouse_pos() == nil, 'line==0/column==0 的命中返回 nil')

  -- 模拟仅 column == 0（垂直分隔线）
  vim.fn.getmousepos = function()
    return { winid = 5, line = 3, column = 0 }
  end
  ok(controller._get_mouse_pos() == nil, 'column==0 的命中返回 nil')

  -- 正常命中仍返回 pos
  vim.fn.getmousepos = function()
    return { winid = 5, line = 3, column = 4 }
  end
  local p = controller._get_mouse_pos()
  ok(p ~= nil and p.line == 3 and p.column == 4, '正常命中（line/column > 0）正常返回 pos')

  vim.fn.getmousepos = saved
end

print('\n=== BUG #56: min_show_time 已从类型/默认值移除 ===')
do
  local f = io.open(root .. 'init.lua', 'r')
  local content = f and f:read('*a') or ''
  if f then f:close() end
  ok(content ~= '' and content:find('min_show_time') == nil, 'init.lua 中无 min_show_time（类型与默认值均已移除）')

  -- README 同步移除
  local rf = io.open(project_root .. 'README.md', 'r')
  local rcontent = rf and rf:read('*a') or ''
  if rf then rf:close() end
  ok(rcontent ~= '' and rcontent:find('min_show_time') == nil, 'README 中无 min_show_time')
end

print(string.format('\n结果：%d 通过，%d 失败\n', pass, fail))
if fail > 0 then
  vim.cmd('cquit 1')
end
