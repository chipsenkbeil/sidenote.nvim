local window = require("sidenote.window")

---@return integer
local function scratch()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "note text" })
    return bufnr
end

describe("window.open split", function()
    it("opens a window showing the buffer", function()
        local bufnr = scratch()
        local winid = window.open(bufnr, { style = "split", position = "right", size = 30 })
        assert.eq(vim.api.nvim_win_get_buf(winid), bufnr)
        window.close(winid)
    end)

    it("honours the configured side", function()
        local winid = window.open(scratch(), { style = "split", position = "right", size = 30 })
        assert.eq(vim.api.nvim_win_get_config(winid).split, "right")
        window.close(winid)
    end)

    it("honours the configured width", function()
        local winid = window.open(scratch(), { style = "split", position = "right", size = 34 })
        assert.eq(vim.api.nvim_win_get_width(winid), 34)
        window.close(winid)
    end)

    it("treats size as height for a horizontal split", function()
        local winid = window.open(scratch(), { style = "split", position = "bottom", size = 8 })
        assert.eq(vim.api.nvim_win_get_height(winid), 8)
        window.close(winid)
    end)

    it("maps the config's top and bottom onto the API's above and below", function()
        -- Users configure top/bottom; nvim_open_win speaks above/below
        local winid = window.open(scratch(), { style = "split", position = "top", size = 6 })
        assert.eq(vim.api.nvim_win_get_config(winid).split, "above")
        window.close(winid)
    end)
end)

describe("window.open float", function()
    it("opens a floating window", function()
        local winid = window.open(scratch(), { style = "float", size = 40 })
        assert.eq(vim.api.nvim_win_get_config(winid).relative, "editor")
        window.close(winid)
    end)
end)

describe("window.open focus", function()
    it("leaves the cursor where it was by default", function()
        local before = vim.api.nvim_get_current_win()
        local winid = window.open(scratch(), { style = "split", position = "right", size = 20 })
        assert.eq(vim.api.nvim_get_current_win(), before)
        window.close(winid)
    end)

    it("moves the cursor into the window when asked", function()
        local winid =
            window.open(scratch(), { style = "split", position = "right", size = 20, focus = true })
        assert.eq(vim.api.nvim_get_current_win(), winid)
        window.close(winid)
    end)
end)

describe("window.close", function()
    it("closes a window", function()
        local winid = window.open(scratch(), { style = "split", position = "right", size = 20 })
        window.close(winid)
        assert.falsy(vim.api.nvim_win_is_valid(winid))
    end)

    it("is safe on a window that is already gone", function()
        local winid = window.open(scratch(), { style = "split", position = "right", size = 20 })
        window.close(winid)
        window.close(winid)
    end)

    it("is safe on nil", function()
        window.close(nil)
    end)
end)
