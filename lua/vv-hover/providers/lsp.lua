-- ================================
-- vv-hover.nvim - LSP Provider
-- ================================

local M = {}

---@type VVHoverConfig|nil
local config = nil

---创建 LSP provider
---@param cfg table 配置
---@return function provider 函数
function M.new(cfg)
  config = cfg
  return M._get_hover_content
end

---构建 LSP position 参数
---getmousepos 返回的 column 是 1-based 字节列；LSP 的 character 必须是 0-based
---因此先把 1-based 字节列转为 0-based 并 clamp，再做 UTF 编码换算
---@param ctx table 上下文信息（含 row、col、line_text）
---@param encoding string LSP offset_encoding（如 'utf-8' / 'utf-16'）
---@return table position { line = 0-based 行号, character = 0-based 字符索引 }
function M._build_position(ctx, encoding)
  local row = ctx.row
  local line = ctx.line_text or ""

  -- 1-based 字节列 -> 0-based 字节列，clamp 到 [0, #line]
  local col = math.max((ctx.col or 1) - 1, 0)
  col = math.min(col, #line)

  return {
    line = row - 1,
    character = vim.str_utfindex(line, encoding, col),
  }
end

---获取 LSP hover 内容
---@param ctx table 上下文信息
---@param callback function 回调函数 function(result) -> nil
---@return boolean 是否成功发起请求
function M._get_hover_content(ctx, callback)
  if not ctx or not ctx.bufnr or not ctx.winid then
    return false
  end

  if not config then
    return false
  end

  -- buffer 校验
  if not vim.api.nvim_buf_is_valid(ctx.bufnr) then
    return false
  end

  if config.behavior.only_normal_buf and vim.bo[ctx.bufnr].buftype ~= "" then
    return false
  end

  -- 获取支持 hover 的 LSP 客户端（遍历时按 clients 顺序保证确定性）
  local clients = vim.lsp.get_clients({ bufnr = ctx.bufnr, method = "textDocument/hover" })
  if not clients or #clients == 0 then
    return false
  end

  -- 向【所有】hover-capable 客户端发请求，对齐原生 vim.lsp.buf.hover
  -- 只问「第一个」客户端会踩坑：如 tailwindcss 排在 tsgo 前，对普通代码恒返回
  -- null，真正有内容的 tsgo 反而问不到 → hover 静默失效
  -- params 用函数式：每个客户端按各自 offset_encoding 单独换算 0-based character
  -- （tailwindcss 用 utf-16、tsgo 用 utf-8，编码不同必须分别构建）
  local make_params = function(client)
    return {
      textDocument = { uri = vim.uri_from_bufnr(ctx.bufnr) },
      position = M._build_position(ctx, client.offset_encoding),
    }
  end

  vim.lsp.buf_request_all(ctx.bufnr, "textDocument/hover", make_params, function(results)
    local util = vim.lsp.util

    -- 按 clients 顺序取第一个非空结果（pairs 顺序不确定，遍历 clients 保确定性）
    for _, client in ipairs(clients) do
      local resp = results[client.id]
      if resp and not resp.err and resp.result and resp.result.contents then
        local markdown_lines = util.convert_input_to_markdown_lines(resp.result.contents)
        if markdown_lines and M._has_content(markdown_lines) then
          callback({
            lines = markdown_lines,
            filetype = "markdown",
          })
          return
        end
      end
    end

    callback(nil)
  end)

  return true
end

---判断 markdown 行是否含有效内容（过滤纯空白 / 空响应）
---@param lines string[]
---@return boolean
function M._has_content(lines)
  for _, line in ipairs(lines) do
    if line:match("%S") then
      return true
    end
  end
  return false
end

return M
