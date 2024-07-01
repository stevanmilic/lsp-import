local servers = require("lspimport.servers")

local LspImport = {}

---@return vim.Diagnostic[]
local get_unresolved_import_errors = function()
    local line, _ = unpack(vim.api.nvim_win_get_cursor(0))
    local diagnostics = vim.diagnostic.get(0, { lnum = line - 1, severity = vim.diagnostic.severity.ERROR })
    if vim.tbl_isempty(diagnostics) then
        return {}
    end
    return vim.tbl_filter(function(diagnostic)
        local server = servers.get_server(diagnostic)
        if server == nil then
            return false
        end
        return server.is_unresolved_import_error(diagnostic)
    end, diagnostics)
end

---@param diagnostics vim.Diagnostic[]
---@return vim.Diagnostic|nil
local get_diagnostic_under_cursor = function(diagnostics)
    local cursor = vim.api.nvim_win_get_cursor(0)
    local row, col = cursor[1] - 1, cursor[2]
    for _, d in ipairs(diagnostics) do
        if d.lnum <= row and d.col <= col and d.end_lnum >= row and d.end_col >= col then
            return d
        end
    end
    return nil
end

---@param result vim.lsp.CompletionResult Result of `textDocument/completion`
---@param prefix string prefix to filter the completion items
---@return table[]
local lsp_to_complete_items = function(result, prefix)
    if vim.fn.has("nvim-0.10.0") == 1 then
        return vim.lsp._completion._lsp_to_complete_items(result, prefix)
    else
        return require("vim.lsp.util").text_document_completion_list_to_complete_items(result, prefix)
    end
end

---@param server lspimport.Server
---@param result lsp.CompletionList|lsp.CompletionItem[] Result of `textDocument/completion`
---@param unresolved_import string
---@return table[]
local get_auto_import_complete_items = function(server, result, unresolved_import)
    local items = lsp_to_complete_items(result, unresolved_import)
    if vim.tbl_isempty(items) then
        return {}
    end
    return vim.tbl_filter(function(item)
        return item.word == unresolved_import
            and item.user_data
            and item.user_data.nvim
            and item.user_data.nvim.lsp.completion_item
            and item.user_data.nvim.lsp.completion_item.labelDetails
            and item.user_data.nvim.lsp.completion_item.labelDetails.description
            and item.user_data.nvim.lsp.completion_item.additionalTextEdits
            and not vim.tbl_isempty(item.user_data.nvim.lsp.completion_item.additionalTextEdits)
            and server.is_auto_import_completion_item(item)
    end, items)
end

---@param item any|nil
---@param bufnr integer
local resolve_import = function(item, bufnr)
    if item == nil then
        return
    end
    local text_edits = item.user_data.nvim.lsp.completion_item.additionalTextEdits
    vim.lsp.util.apply_text_edits(text_edits, bufnr, "utf-8")
end

---@param item any
local format_import = function(item)
    return item.abbr .. " " .. item.kind .. " " .. item.user_data.nvim.lsp.completion_item.labelDetails.description
end

---@param items_text table[string]
---@return integer
local create_floating_window = function(items_text)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, items_text)

    local width = 0
    for _, text in ipairs(items_text) do
        local length = #text
        if length > width then
            width = length
        end
    end

    local height = #items_text

    local opts = {
        style = "minimal",
        relative = "cursor",
        width = width,
        height = height,
        row = 1,
        col = 3,
    }

    vim.api.nvim_open_win(buf, true, opts)
    return buf
end

---@param items table[]
---@param bufnr integer
local handle_floating_window_selection = function(items, bufnr)
    local buf = vim.api.nvim_get_current_buf()

    -- Set up Enter key mapping
    vim.api.nvim_buf_set_keymap(buf, "n", "<CR>", "", {
        noremap = true,
        silent = true,
        callback = function()
            local cursor_pos = vim.api.nvim_win_get_cursor(0)
            local line = cursor_pos[1]
            local selected_item = items[line]
            if selected_item then
                print("Selected item: " .. selected_item.abbr)
                resolve_import(selected_item, bufnr)
                vim.api.nvim_win_close(0, true)
            end
        end,
    })
end

---@param server lspimport.Server
---@param result lsp.CompletionList|lsp.CompletionItem[] Result of `textDocument/completion`
---@param unresolved_import string
---@param bufnr integer
local lsp_completion_handler = function(server, result, unresolved_import, bufnr)
    if vim.tbl_isempty(result or {}) then
        vim.notify("no import found for " .. unresolved_import)
        return
    end
    local items = get_auto_import_complete_items(server, result, unresolved_import)
    if vim.tbl_isempty(items) then
        vim.notify("no import found for " .. unresolved_import)
        return
    end
    if #items == 1 then
        resolve_import(items[1], bufnr)
    else
        local item_texts = vim.tbl_map(format_import, items)
        create_floating_window(item_texts)
        handle_floating_window_selection(items, bufnr)
    end
end

---@param diagnostic vim.Diagnostic
local lsp_completion = function(diagnostic)
    local unresolved_import = vim.api.nvim_buf_get_text(
        diagnostic.bufnr,
        diagnostic.lnum,
        diagnostic.col,
        diagnostic.end_lnum,
        diagnostic.end_col,
        {}
    )
    if vim.tbl_isempty(unresolved_import) then
        vim.notify("cannot find diagnostic symbol")
        return
    end
    local server = servers.get_server(diagnostic)
    if server == nil then
        vim.notify("cannot find server implementation for lsp import")
        return
    end
    local params = {
        textDocument = vim.lsp.util.make_text_document_params(0),
        position = { line = diagnostic.lnum, character = diagnostic.end_col },
    }
    return vim.lsp.buf_request(diagnostic.bufnr, "textDocument/completion", params, function(_, result)
        lsp_completion_handler(server, result, unresolved_import[1], diagnostic.bufnr)
    end)
end

LspImport.import = function()
    vim.schedule(function()
        local diagnostics = get_unresolved_import_errors()
        if vim.tbl_isempty(diagnostics) then
            vim.notify("no unresolved import error")
            return
        end
        local diagnostic = get_diagnostic_under_cursor(diagnostics)
        lsp_completion(diagnostic or diagnostics[1])
    end)
end

return LspImport
