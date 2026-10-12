local M = {}

M.last_op = "copy"

function M.copy_node_path()
    local api = require("nvim-tree.api")
    local nodes = api.marks.list()

    if #nodes == 0 then
        local mode = vim.fn.mode()
        if mode == "v" or mode == "V" or mode == "\22" then
            local sline = vim.fn.line("v")
            local eline = vim.fn.line(".")
            if sline > eline then
                sline, eline = eline, sline
            end

            local curr_cursor = vim.api.nvim_win_get_cursor(0)
            for i = sline, eline do
                vim.api.nvim_win_set_cursor(0, { i, 0 })
                local node = api.tree.get_node_under_cursor()
                if node and node.name ~= ".." then
                    table.insert(nodes, node)
                end
            end
            vim.api.nvim_win_set_cursor(0, curr_cursor)
        else
            local node = api.tree.get_node_under_cursor()
            if node then
                table.insert(nodes, node)
            end
        end
    end

    local paths = {}
    for _, node in ipairs(nodes) do
        if node.absolute_path then
            table.insert(paths, node.absolute_path)
        end
    end

    if #paths > 0 then
        vim.fn.setreg("+", table.concat(paths, "\n"))
        vim.notify("Copied " .. #paths .. " path(s) to system clipboard")

        -- Add visual wave indicator (NvimTreeCopiedHL) for copied nodes
        api.fs.clear_clipboard()
        for _, node in ipairs(nodes) do
            if node.absolute_path then
                api.fs.copy.node(node)
            end
        end

        -- Clear marks after copying to match expected "copy" behavior
        api.marks.clear()
    end

    vim.cmd("normal! \27")
end

function M.cut_node()
    local api = require("nvim-tree.api")
    local node = api.tree.get_node_under_cursor()
    if not node then
        print("No node selected")
        return
    end
    local path = node.absolute_path
    vim.fn.setreg("+", path)
    vim.fn.setreg("*", path)
    M.last_op = "cut"
    print("Marked for cut: " .. path)
end

function M.run_executable_detached()
    local api = require("nvim-tree.api")
    local node = api.tree.get_node_under_cursor()
    if not node then
        return
    end
    local path = node.absolute_path
    if vim.ui and vim.ui.open then
        vim.ui.open(path)
    elseif vim.fn.has("win32") == 1 then
        vim.cmd('silent !start "" "' .. path .. '"')
    elseif vim.fn.has("mac") == 1 then
        vim.cmd('silent !open "' .. path .. '"')
    else
        vim.cmd('silent !xdg-open "' .. path .. '"')
    end
end

function M.copy_node_content()
    local api = require("nvim-tree.api")
    local node = api.tree.get_node_under_cursor()
    if not node then
        print("No node selected")
        return
    end
    local path = node.absolute_path
    path = path:gsub("/", "\\")

    if vim.fn.filereadable(path) == 0 and vim.fn.isdirectory(path) == 0 then
        print("Path not readable: " .. path)
        return
    end

    local ps_path = path:gsub("'", "''")
    local script = string.format(
        "Add-Type -AssemblyName System.Windows.Forms; $files = New-Object System.Collections.Specialized.StringCollection; $files.Add('%s'); [System.Windows.Forms.Clipboard]::SetFileDropList($files)",
        ps_path
    )

    local output = vim.fn.system({ "powershell", "-NoProfile", "-Command", script })
    if vim.v.shell_error == 0 then
        print("Copied file to system clipboard (Explorer compatible): " .. path)
    else
        print("Failed to copy file to clipboard: " .. output)
    end
end

function M.cut_node_content()
    local api = require("nvim-tree.api")
    local node = api.tree.get_node_under_cursor()
    if not node then
        print("No node selected")
        return
    end
    local path = node.absolute_path
    path = path:gsub("/", "\\")

    if vim.fn.filereadable(path) == 0 and vim.fn.isdirectory(path) == 0 then
        print("Path not readable: " .. path)
        return
    end

    local ps_path = path:gsub("'", "''")
    -- In Windows, "cut" is set by Preferred DropEffect = 2
    local script = string.format(
        "Add-Type -AssemblyName System.Windows.Forms; $files = New-Object System.Collections.Specialized.StringCollection; $files.Add('%s'); $data = New-Object System.Windows.Forms.DataObject; $data.SetFileDropList($files); $ms = New-Object System.IO.MemoryStream; $ms.Write([byte[]](2,0,0,0), 0, 4); $data.SetData('Preferred DropEffect', $ms); [System.Windows.Forms.Clipboard]::SetDataObject($data, $true)",
        ps_path
    )

    local output = vim.fn.system({ "powershell", "-NoProfile", "-Command", script })
    if vim.v.shell_error == 0 then
        print("Marked for cut in system clipboard (Explorer compatible): " .. path)
    else
        print("Failed to cut file to clipboard: " .. output)
    end
end

function M.build_copy_target_path(sourcePath, destDir)
    local sourceName = vim.fn.fnamemodify(sourcePath, ":t")
    local sourceRoot = vim.fn.fnamemodify(sourceName, ":r")
    local sourceExt = vim.fn.fnamemodify(sourceName, ":e")
    local suffix = "(copy)"
    local index = 1

    while true do
        local targetName
        if vim.fn.isdirectory(sourcePath) == 1 then
            targetName = sourceName .. suffix .. (index > 1 and (" " .. index) or "")
        elseif sourceExt == "" or sourceRoot == sourceName then
            targetName = sourceName .. suffix .. (index > 1 and (" " .. index) or "")
        else
            targetName = sourceRoot
                .. suffix
                .. (index > 1 and (" " .. index) or "")
                .. "."
                .. sourceExt
        end

        local targetPath = destDir .. "/" .. targetName
        if vim.fn.glob(targetPath) == "" then
            return targetPath
        end
        index = index + 1
    end
end

function M.paste_node()
    local api = require("nvim-tree.api")
    local clipboard = vim.fn.getreg("+")
    if clipboard == "" then
        clipboard = vim.fn.getreg("*")
    end

    if clipboard == "" then
        print("Clipboard is empty.")
        return
    end

    local paths = vim.split(clipboard, "[\r\n]+", { trimempty = true })
    local node = api.tree.get_node_under_cursor()
    if not node then
        print("No destination node selected")
        return
    end

    local destDir = node.absolute_path
    if node.type ~= "directory" then
        destDir = vim.fn.fnamemodify(destDir, ":h")
    end

    local success_count = 0
    for _, sourcePath in ipairs(paths) do
        sourcePath = sourcePath:gsub("^%s*(.-)%s*$", "%1")

        if vim.fn.filereadable(sourcePath) == 1 or vim.fn.isdirectory(sourcePath) == 1 then
            local sourceName = vim.fn.fnamemodify(sourcePath, ":t")
            local targetPath = destDir .. "/" .. sourceName

            if targetPath == sourcePath then
                if M.last_op ~= "cut" then
                    targetPath = M.build_copy_target_path(sourcePath, destDir)
                end
            end

            if targetPath ~= sourcePath and vim.fn.glob(targetPath) ~= "" then
                print("Target already exists, skipping: " .. targetPath)
            else
                local output
                if vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1 then
                    local script
                    if M.last_op == "cut" then
                        script = string.format(
                            "Move-Item -Path '%s' -Destination '%s' -Force",
                            sourcePath:gsub("'", "''"),
                            targetPath:gsub("'", "''")
                        )
                    else
                        script = string.format(
                            "Copy-Item -Path '%s' -Destination '%s' -Recurse -Force",
                            sourcePath:gsub("'", "''"),
                            targetPath:gsub("'", "''")
                        )
                    end
                    output = vim.fn.system({ "powershell", "-NoProfile", "-Command", script })
                else
                    local cmd = M.last_op == "cut"
                            and string.format(
                                'mv "%s" "%s"',
                                sourcePath:gsub('"', '\\"'),
                                targetPath:gsub('"', '\\"')
                            )
                        or string.format(
                            'cp -r "%s" "%s"',
                            sourcePath:gsub('"', '\\"'),
                            targetPath:gsub('"', '\\"')
                        )
                    output = vim.fn.system(cmd)
                end

                if vim.v.shell_error == 0 then
                    success_count = success_count + 1
                else
                    print("Error processing " .. sourcePath .. ": " .. output)
                end
            end
        else
            print("Invalid path skipped: " .. sourcePath)
        end
    end

    if success_count > 0 then
        print((M.last_op == "cut" and "Moved " or "Copied ") .. success_count .. " item(s).")
        if M.last_op == "cut" then
            M.last_op = "copy"
        end
        api.tree.reload()
    end
end

function M.paste_system_clipboard_content()
    local api = require("nvim-tree.api")
    local node = api.tree.get_node_under_cursor()
    if not node then
        print("No node selected")
        return
    end

    local destDir = node.absolute_path
    if node.type ~= "directory" then
        destDir = vim.fn.fnamemodify(destDir, ":h")
    end

    local timestamp = vim.fn.strftime("%Y%m%d_%H%M%S")
    local output

    if vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1 then
        local destDir_ps = destDir:gsub("'", "''")
        local script = string.format(
            [[Add-Type -AssemblyName System.Windows.Forms; Add-Type -AssemblyName System.Drawing; $dest = '%s'; if ([System.Windows.Forms.Clipboard]::ContainsFileDropList()) { $files = [System.Windows.Forms.Clipboard]::GetFileDropList(); foreach ($f in $files) { Copy-Item -Path $f -Destination $dest -Recurse -Force }; Write-Host 'Copied files' } elseif ([System.Windows.Forms.Clipboard]::ContainsImage()) { $img = [System.Windows.Forms.Clipboard]::GetImage(); $path = Join-Path $dest ('clipboard_image_%s.png'); $img.Save($path, [System.Drawing.Imaging.ImageFormat]::Png); Write-Host ('Saved image to ' + $path) } elseif ([System.Windows.Forms.Clipboard]::ContainsText()) { $txt = [System.Windows.Forms.Clipboard]::GetText(); $path = Join-Path $dest ('clipboard_text_%s.txt'); [IO.File]::WriteAllText($path, $txt); Write-Host ('Saved text to ' + $path) } else { Write-Host 'Clipboard is empty or unsupported format' }]],
            destDir_ps,
            timestamp,
            timestamp
        )
        output = vim.fn.system({ "powershell", "-NoProfile", "-Command", script })
    elseif vim.fn.has("mac") == 1 or vim.fn.has("macunix") == 1 then
        local destDir_sh = vim.fn.escape(destDir, "'")
        local cmd = string.format(
            [[sh -c 'if pbpaste | grep -q "^/"; then for file in $(pbpaste); do cp -r "$file" '"'%s'"'/ 2>/dev/null; done; echo "Copied paths"; else pbpaste > '"'%s/clipboard_text_%s.txt'"'; echo "Saved text"; fi']],
            destDir_sh,
            destDir_sh,
            timestamp
        )
        output = vim.fn.system(cmd)
    else
        local destDir_sh = vim.fn.escape(destDir, "'")
        local cmd = string.format(
            [[sh -c 'if xclip -selection clipboard -o | grep -q "^/"; then for file in $(xclip -selection clipboard -o); do cp -r "$file" '"'%s'"'/ 2>/dev/null; done; echo "Copied paths"; else xclip -selection clipboard -o > '"'%s/clipboard_text_%s.txt'"'; echo "Saved text"; fi']],
            destDir_sh,
            destDir_sh,
            timestamp
        )
        output = vim.fn.system(cmd)
    end

    print(output)

    api.tree.reload()
end

function M.remove_buffers_not_under_root()
    local api = require("nvim-tree.api")
    local root_node = api.tree.get_nodes()
    if not root_node or not root_node.absolute_path then
        return
    end

    local root_path = vim.fn.fnamemodify(root_node.absolute_path, ":p")
    root_path = root_path:gsub("\\", "/")

    local buffers_to_delete = {}
    local listed_buffers = 0

    for _, buf in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
        if vim.bo[buf.bufnr].filetype ~= "NvimTree" then
            listed_buffers = listed_buffers + 1
            local buf_name = vim.fn.fnamemodify(buf.name, ":p"):gsub("\\", "/")
            if buf.name ~= "" and string.find(buf_name, root_path, 1, true) ~= 1 then
                table.insert(buffers_to_delete, buf.bufnr)
            end
        end
    end

    local will_be_empty = (listed_buffers == #buffers_to_delete)

    if will_be_empty and #buffers_to_delete > 0 then
        if vim.bo.filetype ~= "NvimTree" then
            vim.cmd("enew")
        else
            local found_normal_win = false
            for _, win in ipairs(vim.fn.getwininfo()) do
                if vim.bo[vim.fn.winbufnr(win.winid)].filetype ~= "NvimTree" then
                    vim.fn.win_execute(win.winid, "enew")
                    found_normal_win = true
                    break
                end
            end
            if not found_normal_win then
                vim.cmd("wincmd p")
                vim.cmd("enew")
                vim.cmd("wincmd p")
            end
        end
    end

    for _, bufnr in ipairs(buffers_to_delete) do
        for _, win in ipairs(vim.fn.getwininfo()) do
            if win.bufnr == bufnr then
                if vim.bo[vim.fn.winbufnr(win.winid)].filetype ~= "NvimTree" then
                    vim.fn.win_execute(win.winid, "enew")
                end
            end
        end
        vim.cmd("silent! bdelete " .. bufnr)
    end
end

local function get_path(args)
    if args and args[1] and args[1] ~= "" then
        return args[1]
    end

    if vim.bo.filetype == "nerdtree" and vim.g.NERDTreeFileNode then
        local node = vim.fn["g:NERDTreeFileNode.GetSelected"]()
        if node and node.path then
            return node.path:str()
        end
    end

    -- Support nvim-tree as well since it's common in modern setups
    if vim.bo.filetype == "NvimTree" then
        local status_ok, api = pcall(require, "nvim-tree.api")
        if status_ok then
            local node = api.tree.get_node_under_cursor()
            if node and node.absolute_path then
                return node.absolute_path
            end
        end
    end

    -- Support oil.nvim (since it's the default file browser)
    if vim.bo.filetype == "oil" then
        local status_ok, oil = pcall(require, "oil")
        if status_ok then
            local dir = oil.get_current_dir()
            local entry = oil.get_cursor_entry()
            if dir and entry then
                return dir .. entry.name
            elseif dir then
                return dir
            end
        end
    end

    return vim.fn.expand("%:p")
end

function M.zip(...)
    local path = get_path({ ... })
    if not path or path == "" then
        vim.api.nvim_err_writeln("No path provided")
        return
    end

    path = vim.fn.fnamemodify(path, ":p")
    -- remove trailing slash
    path = path:gsub("[/\\]$", "")

    local dir = vim.fn.fnamemodify(path, ":h")
    local name = vim.fn.fnamemodify(path, ":t")
    local sep = (vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1) and "\\" or "/"
    local zip_file = dir .. sep .. name .. ".zip"

    if vim.fn.executable("7z") == 0 then
        vim.api.nvim_err_writeln("7z is not found in PATH")
        return
    end

    local cmd = { "7z", "a", zip_file, path }
    vim.fn.jobstart(cmd, {
        on_exit = function(_, code)
            vim.schedule(function()
                if code == 0 then
                    print(string.format("Successfully zipped to %s", zip_file))
                else
                    vim.api.nvim_err_writeln(
                        string.format("Failed to zip %s (exit code: %s)", path, code)
                    )
                end
            end)
        end,
    })
    print(string.format("Zipping %s to %s...", path, zip_file))
end

function M.unzip(...)
    local path = get_path({ ... })
    if not path or path == "" then
        vim.api.nvim_err_writeln("No path provided")
        return
    end

    path = vim.fn.fnamemodify(path, ":p")

    local dir = vim.fn.fnamemodify(path, ":h")
    local name_no_ext = vim.fn.fnamemodify(path, ":t:r")
    local sep = (vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1) and "\\" or "/"
    local out_dir = dir .. sep .. name_no_ext

    if vim.fn.executable("7z") == 0 then
        vim.api.nvim_err_writeln("7z is not found in PATH")
        return
    end

    local cmd = { "7z", "x", path, "-o" .. out_dir }
    vim.fn.jobstart(cmd, {
        on_exit = function(_, code)
            vim.schedule(function()
                if code == 0 then
                    print(string.format("Successfully unzipped to %s", out_dir))
                else
                    vim.api.nvim_err_writeln(
                        string.format("Failed to unzip %s (exit code: %s)", path, code)
                    )
                end
            end)
        end,
    })
    print(string.format("Unzipping %s to %s...", path, out_dir))
end

function M.change_root(path)
    if not path or path == "" then
        path = vim.fn.getcwd()
    end
    path = vim.fn.fnamemodify(path, ":p")
    -- remove trailing slash
    path = path:gsub("[/\\]$", "")

    if vim.fn.isdirectory(path) == 0 then
        vim.api.nvim_err_writeln("Path is not a directory: " .. path)
        return
    end

    vim.api.nvim_set_current_dir(path)
    local api = require("nvim-tree.api")
    api.tree.change_root(path)
    print("CWD and nvim-tree root changed to: " .. path)
end

return M
