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

print('\n=== lifecycle: external global changes remain owned by their writer ===')
do
  local controller = dofile(root .. 'controller.lua')
  local mock_view = { close = function() end, is_open = function() return false end, is_mouse_inside = function() return false end }
  local mock_config = {
    timing = { hover_delay = 500, close_delay = 300 },
    ui = {},
    behavior = { close_on_move = true, close_on_insert = false, only_normal_buf = true },
  }
  local original_mousemoveevent = vim.o.mousemoveevent
  vim.keymap.set('n', '<MouseMove>', '<cmd>let g:vv_hover_old = 1<cr>', { desc = 'old MouseMove' })
  vim.o.mousemoveevent = false
  controller.setup(mock_config, mock_view, function() end)
  controller.enable()
  vim.keymap.set('n', '<MouseMove>', '<cmd>let g:vv_hover_external = 1<cr>', { desc = 'external MouseMove' })
  vim.o.mousemoveevent = false
  controller.disable()
  ok(vim.fn.maparg('<MouseMove>', 'n', false, true).desc == 'external MouseMove',
    'disable keeps a MouseMove mapping installed after vv-hover')
  ok(vim.o.mousemoveevent == false, 'disable keeps mousemoveevent changed after vv-hover')
  pcall(vim.keymap.del, 'n', '<MouseMove>')
  vim.o.mousemoveevent = original_mousemoveevent
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
  ok(during_map.desc == 'Scroll hover up', 'enable 后滚轮映射被插件覆盖')

  controller.disable()

  -- disable 后应恢复原始映射
  local after_map = vim.fn.maparg('<ScrollWheelUp>', 'n', false, true)
  ok(after_map.desc == 'test scroll up', 'disable 后滚轮映射恢复为自定义映射')

  -- 清理
  pcall(vim.keymap.del, 'n', '<ScrollWheelUp>')
end

print('\n=== lifecycle: MouseMove mapping restore ===')
do
  local controller = dofile(root .. 'controller.lua')
  local mock_view = { close = function() end, is_open = function() return false end, is_mouse_inside = function() return false end }
  local mock_config = {
    timing = { hover_delay = 500, close_delay = 300 },
    ui = {},
    behavior = { close_on_move = true, close_on_insert = false, only_normal_buf = true },
  }
  controller.setup(mock_config, mock_view, function() end)

  local original = function() return 'existing mouse move' end
  vim.keymap.set('n', '<MouseMove>', original, { desc = 'existing mouse move' })
  controller.enable()
  ok(vim.fn.maparg('<MouseMove>', 'n', false, true).desc == 'Show hover', 'enable captures and replaces MouseMove')
  controller.disable()
  local restored = vim.fn.maparg('<MouseMove>', 'n', false, true)
  ok(restored.desc == 'existing mouse move', 'disable restores MouseMove mapping')
  pcall(vim.keymap.del, 'n', '<MouseMove>')
end

print('\n=== lifecycle: buffer-local mapping isolation ===')
do
  local controller = dofile(root .. 'controller.lua')
  local mock_view = { close = function() end, is_open = function() return false end, is_mouse_inside = function() return false end }
  local mock_config = {
    timing = { hover_delay = 500, close_delay = 300 },
    ui = {},
    behavior = { close_on_move = true, close_on_insert = false, only_normal_buf = true },
  }
  controller.setup(mock_config, mock_view, function() end)

  local original_buf = vim.api.nvim_get_current_buf()
  local test_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(test_buf)
  vim.keymap.set('n', '<MouseMove>', '<cmd>let b:vv_hover_local = 1<cr>', {
    buffer = test_buf,
    desc = 'buffer-local MouseMove',
  })

  controller.enable()
  controller.disable()

  local local_map = vim.fn.maparg('<MouseMove>', 'n', false, true)
  local global_map
  for _, map in ipairs(vim.api.nvim_get_keymap('n')) do
    if map.lhs == '<MouseMove>' then global_map = map end
  end
  ok(local_map.desc == 'buffer-local MouseMove', 'disable preserves buffer-local MouseMove')
  ok(global_map == nil, 'disable does not leak buffer-local MouseMove globally')

  vim.api.nvim_set_current_buf(original_buf)
  vim.api.nvim_buf_delete(test_buf, { force = true })
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

print('\n=== BUG #57: 普通窗口滚轮交给 vv-utils.scroll ===')
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

  local old_scroll = package.loaded['vv-utils.scroll']
  local called_direction = nil
  local called_win = nil

  package.loaded['vv-utils.scroll'] = {
    mouse = function(direction, winid)
      called_direction = direction
      called_win = winid
      return true
    end,
  }

  controller.setup(mock_config, mock_view, function() end)
  controller.enable()
  controller._on_scroll('down')
  controller.disable()

  ok(called_direction == 'down', '普通窗口滚轮调用 vv-utils.scroll.mouse')
  ok(called_win == vim.api.nvim_get_current_win(), '普通窗口滚轮传入当前窗口兜底')

  package.loaded['vv-utils.scroll'] = old_scroll
end

print('\n=== BUG #58: hover 向所有客户端发请求，取第一个非空结果 ===')
do
  local lsp = dofile(root .. 'providers/lsp.lua')

  -- _has_content 过滤纯空白 / 空响应
  ok(lsp._has_content({ '', '  ', 'x' }) == true, '_has_content：含非空白行 → true')
  ok(lsp._has_content({ '', '   ' }) == false, '_has_content：全空白 → false')

  local provider = lsp.new({ behavior = { only_normal_buf = false } })

  -- 备份待 mock 的 API
  local saved = {
    get_clients = vim.lsp.get_clients,
    buf_request_all = vim.lsp.buf_request_all,
    convert = vim.lsp.util.convert_input_to_markdown_lines,
    uri = vim.uri_from_bufnr,
    valid = vim.api.nvim_buf_is_valid,
  }

  -- 模拟两个客户端：tailwindcss（排前，返回空）+ tsgo（返回内容）
  local c1 = { id = 1, name = 'tailwindcss', offset_encoding = 'utf-16' }
  local c2 = { id = 2, name = 'tsgo', offset_encoding = 'utf-8' }

  vim.api.nvim_buf_is_valid = function() return true end
  vim.uri_from_bufnr = function() return 'file:///x' end
  vim.lsp.get_clients = function() return { c1, c2 } end
  vim.lsp.util.convert_input_to_markdown_lines = function(contents) return contents.lines end
  vim.lsp.buf_request_all = function(_, _, params, handler)
    ok(type(params) == 'function', 'params 以函数式传入（每客户端按各自编码单独构建）')
    handler({
      [1] = { err = nil, result = { contents = { lines = {} } } },          -- 空
      [2] = { err = nil, result = { contents = { lines = { 'TS DOC' } } } }, -- 有内容
    })
  end

  local got = nil
  local ret = provider(
    { bufnr = 1, winid = 1000, row = 1, col = 1, line_text = 'abc' },
    function(result) got = result end
  )

  ok(ret == true, 'provider 成功发起请求返回 true')
  ok(got ~= nil and got.lines and got.lines[1] == 'TS DOC',
    '跳过空响应的 tailwindcss，取到 tsgo 的内容（实际: ' .. vim.inspect(got) .. '）')

  -- 还原
  vim.lsp.get_clients = saved.get_clients
  vim.lsp.buf_request_all = saved.buf_request_all
  vim.lsp.util.convert_input_to_markdown_lines = saved.convert
  vim.uri_from_bufnr = saved.uri
  vim.api.nvim_buf_is_valid = saved.valid
end

print('\n=== BUG #59: M.focus 聚焦浮窗（键盘进窗）===')
do
  package.loaded['vv-hover'] = nil
  package.loaded['vv-hover.controller'] = nil
  package.loaded['vv-hover.view'] = nil
  package.loaded['vv-hover.providers.lsp'] = nil

  local hover = require('vv-hover')
  local view = require('vv-hover.view')
  hover.setup({ enabled = false })

  -- 无浮窗时 focus 返回 false
  local saved_get = view.get_current
  view.get_current = function() return nil, nil end
  ok(hover.focus() == false, '无浮窗时 focus 返回 false')

  -- 造真实浮窗，mock view.get_current 指向它
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'doc line' })
  local fwin = vim.api.nvim_open_win(buf, false,
    { relative = 'editor', row = 1, col = 1, width = 10, height = 1, focusable = true })
  view.get_current = function() return fwin, buf end

  local before = vim.api.nvim_get_current_win()
  ok(hover.focus() == true, '浮窗存在时 focus 返回 true')
  ok(vim.api.nvim_get_current_win() == fwin, 'focus 后当前窗切到浮窗')

  local has_q = false
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, 'n')) do
    if m.lhs == 'q' then has_q = true break end
  end
  ok(has_q, '浮窗 buffer 装了 q 关闭键')

  -- 还原 / 清理
  pcall(vim.api.nvim_set_current_win, before)
  pcall(vim.api.nvim_win_close, fwin, true)
  pcall(vim.api.nvim_buf_delete, buf, { force = true })
  view.get_current = saved_get
  package.loaded['vv-hover'] = nil
  package.loaded['vv-hover.controller'] = nil
  package.loaded['vv-hover.view'] = nil
  package.loaded['vv-hover.providers.lsp'] = nil
end

print(string.format('\n 结果：%d 通过，%d 失败\n', pass, fail))
if fail > 0 then
  vim.cmd('cquit 1')
end
