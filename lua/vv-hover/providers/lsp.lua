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
---getmousepos 返回的 column 是 1-based 字节列；LSP 的 character 必须是 0-based。
---因此先把 1-based 字节列转为 0-based 并 clamp，再做 UTF 编码换算。
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

  -- 获取支持 hover 的 LSP 客户端
  local clients = vim.lsp.get_clients({ bufnr = ctx.bufnr, method = "textDocument/hover" })
  if not clients or #clients == 0 then
    return false
  end

  local hover_client = nil
  for _, client in ipairs(clients) do
    if client:supports_method("textDocument/hover") then
      hover_client = client
      break
    end
  end

  if not hover_client then
    return false
  end

  -- 构建位置参数（LSP 使用 0-based 行号和字符索引）
  local params = {
    textDocument = { uri = vim.uri_from_bufnr(ctx.bufnr) },
    position = M._build_position(ctx, hover_client.offset_encoding),
  }

  -- 发送 LSP 请求
  hover_client:request("textDocument/hover", params, function(err, result)
    if err or not result or not result.contents then
      callback(nil)
      return
    end

    -- 转换为 markdown 行
    local util = vim.lsp.util
    local markdown_lines = util.convert_input_to_markdown_lines(result.contents)

    callback({
      lines = markdown_lines,
      filetype = "markdown",
    })
  end, ctx.bufnr)

  return true
end

return M
