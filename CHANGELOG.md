# Changelog

## [Unreleased]

### Fixed

- LSP hover 列号 off-by-one：`getmousepos` 的 column 是 1-based 字节列，却被原样当作 LSP `position.character`（须 0-based），导致每次 hover 取到鼠标右侧一个字符的符号；现抽出 `M._build_position` 把 1-based 字节列转 0-based 并 clamp 到 `[0,#line]` 再做 `str_utfindex`，`position.line = row-1` 不变
- `hover_timer` / `close_timer` 的 `schedule_wrap` 回调读模块级变量来 close，若期间被新 move 替换了句柄，回调会误关「新的、仍在 pending」的定时器 → 丢 hover / 强关运行中定时器；现两处回调改为捕获本地句柄 `t`，只对 `t` 操作，且仅当模块变量仍 `== t` 时才置空
- `M.toggle` 以 init 的 `config.enabled` 为准并翻转它，但 `M.enable/disable` 从不更新该字段（真实状态在 controller），`:VVHoverDisable` 后首次 `:VVHoverToggle` 变成无操作；现以 `controller.is_enabled()` 为唯一真相源，toggle 读真实状态
- 鼠标在状态栏/窗口分隔线上时 `getmousepos` 返回 `winid!=0` 但 `line==0`/`column==0`，`_get_mouse_pos` 只挡 `winid==0`，放行后构出 `line=-1` 的非法 LSP 请求；现一并过滤 `line==0` / `column==0`
- 移除死配置 `min_show_time`：声明于 `VVHoverTimingConfig` 类型、`default_config.timing` 与 README，但全仓无任何引用（误导性死配置），按 KISS 从类型/默认值/README 一并删除
