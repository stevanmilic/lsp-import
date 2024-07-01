local M = {}

local TITLE_NAMESPACE = 1
local SELECTABLE_NAMESPACE = 2

---@param item any
local format_import = function(item)
    local label = item.user_data.nvim.lsp.completion_item.labelDetails.description or item.user_data.nvim.lsp.completion_item.label
    return label .. " [" .. item.kind .. "]"
end

---@param items table[]
---@param classname string
---@return table[string]
M.create_items_text_with_header = function(items, classname)
    local items_text = { "Import " .. classname .. " from:" }
    for i, item in ipairs(items) do
        table.insert(items_text, " " .. i .. ". " .. format_import(item))
    end
    return items_text
end

---@param items_text table[string]
---@return integer
M.create_floating_window = function(items_text)
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
        border = "rounded",
    }

    local win = vim.api.nvim_open_win(buf, true, opts)
    -- Set cursor to the first selectable item
    vim.api.nvim_win_set_cursor(win, { 2, 0 })

    -- Highlight title
    vim.api.nvim_buf_add_highlight(buf, TITLE_NAMESPACE, "Title", 0, 0, -1)

    -- Add autocommand to highlight the selected line
    vim.cmd([[
      augroup LspImportFloatingWin
        autocmd!
        autocmd CursorMoved <buffer> lua require'lspimport.ui'.highlight_selected_line()
      augroup END
    ]])

    return buf
end

M.highlight_selected_line = function()
    local buf = vim.api.nvim_get_current_buf()
    local cursor_line = vim.fn.line(".") - 1
    -- Clear selectable options highlights
    vim.api.nvim_buf_clear_namespace(buf, SELECTABLE_NAMESPACE, 1, -1)
    -- Apply existing highlight groups
    for i = 1, vim.api.nvim_buf_line_count(buf) - 1 do
        local hl_group = (i == cursor_line) and "CursorLine" or "Normal"

        vim.api.nvim_buf_add_highlight(buf, SELECTABLE_NAMESPACE, hl_group, i, 0, -1)
    end
end

---@param items table[]
---@param bufnr integer
---@param resolve_import function
M.handle_floating_window_selection = function(items, bufnr, resolve_import)
    local buf = vim.api.nvim_get_current_buf()

    -- Set up Enter key mapping
    vim.api.nvim_buf_set_keymap(buf, "n", "<CR>", "", {
        noremap = true,
        silent = true,
        callback = function()
            local cursor_pos = vim.api.nvim_win_get_cursor(0)
            local line = cursor_pos[1]
            if line > 1 then
                local selected_item = items[line - 1] -- Subtract 1 for the header
                if selected_item then
                    resolve_import(selected_item, bufnr)
                    vim.api.nvim_win_close(0, true)
                end
            end
        end,
    })
end

return M
