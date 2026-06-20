# Changelog

## [Unreleased]

### Added

- 键盘进窗读 hover：新增 `M.focus()` 与 `:VVHoverFocus`，把当前浮窗（即便 `ui.focusable=false`，走 `nvim_set_current_win`）设为活动窗口，进窗后可 `<C-e>`/`<C-y>` 滚动、`v`+`y` 复制、`q`/`<Esc>` 关闭；新增 `keymap_focus` 配置项（默认 `false`，走原生 `<C-w>w`；设字符串则注册直达聚焦键）

### Changed

- 默认时序更跟手：`timing.hover_delay` 300 → 250、`timing.close_delay` 300 → 50（同步 README 与一致性测试）

### Fixed

- LSP hover 多客户端只问第一个 → 静默失效：旧逻辑遍历 hover-capable 客户端时 `break` 选「第一个」就只问它一个。当 buffer 同时挂了 `tailwindcss`（id 小、排前，对普通代码恒返回 `null`）与 `tsgo`（真正有 hover）时，永远问到 tailwindcss、拿到空响应、`tsgo` 无机会，hover 整体失效；现改用 `vim.lsp.buf_request_all` 向**所有** hover-capable 客户端发请求（params 用函数式，按各客户端 `offset_encoding` 分别构建 0-based character），按客户端顺序取第一个非空结果，对齐原生 `vim.lsp.buf.hover`；新增 `M._has_content` 过滤纯空白响应
- LSP hover 列号 off-by-one：`getmousepos` 的 column 是 1-based 字节列，却被原样当作 LSP `position.character`（须 0-based），导致每次 hover 取到鼠标右侧一个字符的符号；现抽出 `M._build_position` 把 1-based 字节列转 0-based 并 clamp 到 `[0,#line]` 再做 `str_utfindex`，`position.line = row-1` 不变
- `hover_timer` / `close_timer` 的 `schedule_wrap` 回调读模块级变量来 close，若期间被新 move 替换了句柄，回调会误关「新的、仍在 pending」的定时器 → 丢 hover / 强关运行中定时器；现两处回调改为捕获本地句柄 `t`，只对 `t` 操作，且仅当模块变量仍 `== t` 时才置空
- `M.toggle` 以 init 的 `config.enabled` 为准并翻转它，但 `M.enable/disable` 从不更新该字段（真实状态在 controller），`:VVHoverDisable` 后首次 `:VVHoverToggle` 变成无操作；现以 `controller.is_enabled()` 为唯一真相源，toggle 读真实状态
- 鼠标在状态栏/窗口分隔线上时 `getmousepos` 返回 `winid!=0` 但 `line==0`/`column==0`，`_get_mouse_pos` 只挡 `winid==0`，放行后构出 `line=-1` 的非法 LSP 请求；现一并过滤 `line==0` / `column==0`
- 移除死配置 `min_show_time`：声明于 `VVHoverTimingConfig` 类型、`default_config.timing` 与 README，但全仓无任何引用（误导性死配置），按 KISS 从类型/默认值/README 一并删除
- `is_mouse_inside` 的 bottom/right 判定边界比 top/left 多算一格：内容占 `[winrow, winrow+height-1]`，边框在其外一格，原代码 `winrow+height+1` / `wincol+width+1` 越过边框一格 → 鼠标移到边框下方/右侧一格仍判为「在浮窗内」，close-on-move 被抑制、浮窗发黏；现改为 `- 1 + (has_border and 1 or 0)`，与 top/left 对称
- `view.open` 委托给 `open_floating_preview`，后者用 `nvim_get_current_buf()`（焦点 buffer）记账 `b:lsp_floating_preview` 复用变量与默认 `{CursorMoved,...}` 关闭 autocmd；但本插件是鼠标驱动的，浮窗属于鼠标下的窗口而非焦点窗口 → 记账落到错误 buffer，焦点窗口里无关的 `CursorMoved` 会误关浮窗、复用变量也会误触该 buffer 的 K 浮窗；现把鼠标 `winid` 一路透传到 `view.open`，在被悬停的窗口上下文里调用、`close_events = {}` 自管生命周期，并清掉源 buffer 上的复用变量
- `examples.lua` 示例 2 文档化了 `timing.debounce_ms`，但该键不在 `VVHoverTimingConfig` schema 中、controller/view 也从不读取，复制后是静默无操作（误导性陈旧示例键）；现删除该行
