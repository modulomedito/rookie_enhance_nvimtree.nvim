local M = {}
local actions = require("rookie_enhance_nvimtree.actions")

function M.on_attach(bufnr)
    local api = require("nvim-tree.api")

    local function opts(desc)
        return {
            desc = "nvim-tree: " .. desc,
            buffer = bufnr,
            noremap = true,
            silent = true,
            nowait = true,
        }
    end

    -- default mappings
    api.config.mappings.default_on_attach(bufnr)

    -- custom mappings
    vim.keymap.set("n", "<leader>cd", function()
        local node = api.tree.get_node_under_cursor()
        if node then
            local path = node.absolute_path
            if node.type ~= "directory" then
                path = vim.fn.fnamemodify(path, ":h")
            end
            vim.api.nvim_set_current_dir(path)
            api.tree.change_root(path)
            print("CWD and nvim-tree root changed to: " .. path)
        end
    end, opts("Change CWD and nvim-tree root to node"))

    vim.keymap.set("n", "L", "$", opts("Move to line end"))
    if vim.fn.has("win32") == 1 then
        vim.keymap.set("n", "s", function()
            local node = api.tree.get_node_under_cursor()
            if node then
                vim.cmd('silent !start "" "' .. node.absolute_path .. '"')
            end
        end, opts("Open node with start (win32)"))
    end
    vim.keymap.set("n", "<leader>mc", actions.copy_node_path, opts("Copy node path to clipboard"))
    vim.keymap.set(
        "v",
        "<leader>mc",
        actions.copy_node_path,
        opts("Copy selected paths to clipboard")
    )
    vim.keymap.set("n", "<leader>mx", actions.cut_node, opts("Cut node"))
    vim.keymap.set("n", "<leader>mv", actions.paste_node, opts("Rookie nvim-tree: Paste node"))
    vim.keymap.set(
        "n",
        "<leader>mR",
        actions.run_executable_detached,
        opts("Run executable detached")
    )
    vim.keymap.set(
        "n",
        "<leader>mC",
        actions.copy_node_content,
        opts("Copy node content to clipboard")
    )
    vim.keymap.set(
        "n",
        "<leader>mX",
        actions.cut_node_content,
        opts("Cut node content to clipboard")
    )
    vim.keymap.set(
        "n",
        "<leader>mP",
        actions.paste_system_clipboard_content,
        opts("Paste system clipboard content")
    )
end

function M.setup()
    -- Global mappings
    vim.keymap.set("n", "<C-e>", ":NvimTreeFocus<CR>", { silent = true })
    vim.keymap.set("n", "<C-S-e>", ":NvimTreeFocus<CR>", { silent = true })
    vim.keymap.set("n", "<C-y>", ":NvimTreeToggle<CR>", { silent = true })
    vim.keymap.set("n", "<leader>find", ":NvimTreeFindFile<CR>", { silent = true })

    -- 7zip Commands
    vim.api.nvim_create_user_command("RkZip", function(opts)
        actions.zip(opts.args)
    end, {
        nargs = "?",
        complete = "file",
        desc = "Zip file or directory using 7z",
    })

    vim.api.nvim_create_user_command("RkUnzip", function(opts)
        actions.unzip(opts.args)
    end, { nargs = "?", complete = "file", desc = "Unzip file using 7z" })

    -- 7zip Keymaps
    vim.keymap.set("n", "<leader>mZ", "<cmd>RkZip<CR>", { desc = "7z: Zip current file/dir" })
    vim.keymap.set("n", "<leader>mz", "<cmd>RkUnzip<CR>", { desc = "7z: Unzip current file" })
end

return M
