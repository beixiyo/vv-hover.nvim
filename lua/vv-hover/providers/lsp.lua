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

  -- 构建位置参数（LSP 使用 0-based 行号和 UTF-8 索引）
  local row = ctx.row
  local col = ctx.col
  local line = ctx.line_text or ""
  col = math.min(col, #line)

  local params = {
    textDocument = { uri = vim.uri_from_bufnr(ctx.bufnr) },
    position = {
      line = row - 1,
      character = vim.str_utfindex(line, hover_client.offset_encoding, col),
    },
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
