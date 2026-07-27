-- ==============================================================================
-- Copyright (c) 2026 Panshaogui | MIT License
-- L2C: Transpile Typed Lua into 0-GC Native C for HFT and Embedded Systems.
-- ==============================================================================

-- ==============================================================================
-- L2C 智能提示生成器 (VSCode Snippet & Hover Hack)
-- ==============================================================================
local M = {}

function M.generate(d_file_path)
    local f = io.open(d_file_path, "r")
    if not f then return false end
    
    local snippets = {}
    local hover_dict = {}
    local func_names = {} -- 专门存放关键字的数组，防崩溃！
    local current_doc = {}
    local count = 0
    
    for line in f:lines() do
        local doc_line = line:match("^%-%-%-%s*(.*)")
        if doc_line then
            table.insert(current_doc, doc_line)
        else
            local is_func = false
            -- 1. 匹配标准全局函数
            local func_name, args_str = line:match("global%s+([%w_]+)%s*:%s*function%s*%((.-)%)")
            if func_name then is_func = true end
            -- 2. 匹配 global function 格式
            if not func_name then 
                func_name, args_str = line:match("global%s+function%s+([%w_]+)%s*%((.-)%)")
                if func_name then is_func = true end
            end
            -- 3. 匹配 Record 内部函数
            if not func_name then 
                func_name, args_str = line:match("^%s+([%w_]+)%s*:%s*function%s*%((.-)%)")
                if func_name then is_func = true end
            end
            -- 4. 匹配全局变量 (如 global C_SQLITE: any)
            if not func_name then
                func_name = line:match("global%s+([%w_]+)%s*:%s*[%w_]+")
            end

            if func_name and #current_doc > 0 then
                local body_str = func_name
                
                -- 如果是函数，才处理参数 Snippet 占位符
                if is_func then
                    local body_args = {}
                    local arg_idx = 1
                    if args_str and args_str ~= "" then
                        for arg in args_str:gmatch("([^,]+)") do
                            local clean_arg = arg:match("^%s*([%w_]+)") or "arg"
                            table.insert(body_args, string.format("${%d:%s}", arg_idx, clean_arg))
                            arg_idx = arg_idx + 1
                        end
                    end
                    body_str = func_name .. "(" .. table.concat(body_args, ", ") .. ")"
                end
                
                local description = table.concat(current_doc, "\\n"):gsub('"', '\\"')
                
                table.insert(snippets, string.format([[
                    "%s": {
                        "prefix": "%s",
                        "body": [ "%s" ],
                        "description": "%s"
                    }]], func_name, func_name, body_str, description))

                table.insert(hover_dict, string.format('    "%s": "%s"', func_name, description))
                table.insert(func_names, func_name) -- 存入纯净的关键字数组
                
                count = count + 1
                current_doc = {}
            elseif not line:match("^%s*$") then
                current_doc = {}
            end
        end
    end
    f:close()
    if count == 0 then return true end
    
    -- ==========================================
    -- 1. 写入项目级的 Snippet 补全
    -- ==========================================
    os.execute("mkdir -p .vscode")
    local out = io.open(".vscode/l2c.code-snippets", "w")
    if out then
        out:write("{\n" .. table.concat(snippets, ",\n") .. "\n}")
        out:close()
    end

    -- ==========================================
    -- 2. [终极野路子] 病毒式注入 VSCode Hover 插件！
    -- ==========================================
    local home = os.getenv("HOME")
    if home then
        local ext_dir = home .. "/.vscode/extensions/l2c-hover-hack-0.0.1"
        os.execute("mkdir -p " .. ext_dir)

        local pkg_json = io.open(ext_dir .. "/package.json", "w")
        if pkg_json then
            pkg_json:write([[
                {
                "name": "l2c-hover-hack",
                "displayName": "L2C Hover Hack",
                "version": "0.0.1",
                "publisher": "l2c-engine",
                "engines": { "vscode": "^1.60.0" },
                "activationEvents": [ "*" ],
                "main": "./extension.js",
                "contributes": {}
                }
                ]])
            pkg_json:close()
        end

        local ext_js = io.open(ext_dir .. "/extension.js", "w")
        if ext_js then
            ext_js:write("const vscode = require('vscode');\n")
            ext_js:write("const hoverDict = {\n" .. table.concat(hover_dict, ",\n") .. "\n};\n")
            -- 直接使用纯净的关键字数组，告别正则解析崩溃！
            ext_js:write("const keywords = ['" .. table.concat(func_names, "','") .. "'];\n")
            ext_js:write([[
                function activate(context) {
                    console.log(" [L2C 极客插件已启动] 悬停字典与高亮雷达已加载!");

                    let provider = vscode.languages.registerHoverProvider({ scheme: 'file' }, {
                        provideHover(document, position, token) {
                            const range = document.getWordRangeAtPosition(position);
                            if (!range) return;
                            const word = document.getText(range);
                            if (hoverDict[word]) {
                                const md = new vscode.MarkdownString(hoverDict[word].replace(/\\n/g, '\n\n'));
                                return new vscode.Hover(md);
                            }
                        }
                    });
                    context.subscriptions.push(provider);

                    const l2cDecorationType = vscode.window.createTextEditorDecorationType({
                        color: '#00FFFF',
                        textDecoration: 'underline dotted #00FFFF',
                        fontWeight: 'bold'
                    });

                    function updateDecorations(editor) {
                        if (!editor || keywords.length === 0) return;
                        const text = editor.document.getText();
                        const decorations = [];
                        const regEx = new RegExp('\\b(' + keywords.join('|') + ')\\b', 'g');
                        
                        let match;
                        while ((match = regEx.exec(text))) {
                            const startPos = editor.document.positionAt(match.index);
                            const endPos = editor.document.positionAt(match.index + match[0].length);
                            decorations.push({ range: new vscode.Range(startPos, endPos) });
                        }
                        editor.setDecorations(l2cDecorationType, decorations);
                    }

                    let timeout = undefined;
                    function triggerUpdate(editor) {
                        if (timeout) clearTimeout(timeout);
                        timeout = setTimeout(() => updateDecorations(editor), 300);
                    }

                    vscode.window.onDidChangeActiveTextEditor(editor => { triggerUpdate(editor); }, null, context.subscriptions);
                    vscode.workspace.onDidChangeTextDocument(event => {
                        if (vscode.window.activeTextEditor && event.document === vscode.window.activeTextEditor.document) {
                            triggerUpdate(vscode.window.activeTextEditor);
                        }
                    }, null, context.subscriptions);

                    triggerUpdate(vscode.window.activeTextEditor);
                }
                exports.activate = activate;
                ]])
            ext_js:close()
        end
        print(" [IDE 体验] 专属发光高亮与 Hover 悬停插件均已暴力注入！(共解析 " .. count .. " 个接口)")
    end

    return true
end

return M