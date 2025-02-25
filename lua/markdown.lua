local M = {}

local regex = {
    setex_line_header   = "^%-%-%-%-*",
    setex_equals_header = "^====*",
    atx_header          = "^#",
    unordered_list      = "^%s*[%*%-%+]",
    ordered_list        = "^%s*%d+[%)%.]",
}

-- to make M.backspace only trigger after a new line has been created
local should_run_callback = false
local function key_callback(key)
    local backspace_term = vim.api.nvim_replace_termcodes("<BS>",true, true, true)

    -- It sends some key on o and O "<80><fd>h", which is some special key I didn't ask for.
    if should_run_callback and key ~= '\x80\xfdh' then
        if key == backspace_term then
            M.backspace()
        end
        should_run_callback = false
    end
end

vim.on_key(key_callback)

-- Iterates up or down to find the first occurence of a section marker.
-- line_num is included in the search
local function find_header_or_list(line_num)
    local line_count = vim.api.nvim_buf_line_count(0)

    if line_num < 1 or line_num > line_count then
        -- Tried to find above top or below bottom
        -- Returns nil as if it didn't find anything
        return nil
    end

    -- Special logic to check if the line below is a setex marker, meaning the line passed
    -- is the top of the header
    local line = vim.fn.getline(line_num)
    local setex_line = vim.fn.getline(line_num + 1)
    if setex_line:match(regex.setex_equals_header) and not line:match("^$") then
        return {line = line_num, type = "setex_equals_header"}
    elseif setex_line:match(regex.setex_line_header) and not line:match("^$") then
        return {line = line_num, type = "setex_line_header"}
    end

    while line_num > 0 and line_num <= line_count do
        local line = vim.fn.getline(line_num)
        for name, pattern in pairs(regex) do
            if line:match(pattern) then
                if (name == "setex_equals_header" or name == "setex_line_header") then
                    if vim.fn.getline(line_num-1):match("^$") then
                        -- Not actually a setex header without a title
                        break
                    end
                    line_num = line_num - 1
                end

                return {line = line_num, type = name}
            end
        end

        line_num = line_num - 1
    end
end

local function find_link_under_cursor()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line = vim.fn.getline(cursor[1])
    local column = cursor[2] + 1
    local link_start, link_stop, link
    local start = 1
    repeat
        -- repeats until it finds a link the cursor is inside or ends as nil
        link_start, link_stop, text, url = line:find("%[(.-)%]%((.-)%)", start)
        if link_start then
            start = link_stop + 1
        end
    until not link_start or (link_start <= column and link_stop >= column)


    if link_start then
       return {
            link = "[" .. text .. "](" .. url .. ")",
            start = link_start,
            stop = link_stop,
            text = text,
            url = url
        }
    else
        return nil
    end
end

local function find_word_under_cursor()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local mode = vim.fn.mode(".")
    if mode:find("n") then
        -- normal mode is converted to 1 index while insert mode is
        -- left as 0 index, this is because of how spaces are counted
        cursor[2] = cursor[2] + 1
    end

    local line = vim.fn.getline(cursor[1])
    local word_start, word_stop, word
    local start = 1
    repeat
        -- repeats until it finds a link the cursor is inside or ends as nil
        word_start, word_stop, word = line:find("([^%s]+)", start)
        if word_start then
            start = word_stop + 1
        end
    until not word_start or (word_start <= cursor[2] and word_stop >= cursor[2])

    if word_start then
        return {
            start = word_start,
            stop = word_stop,
            text = word,
        }
    else
        return nil
    end
end


-- Given a the line of a bullet, returns a table of properties of the bullet.
local function parse_bullet(bullet_line)
    local line = vim.fn.getline(bullet_line)
    local bullet = {}

    -- Find what sort of bullet it is (*,-,+ ordered)
    bullet.indent, bullet.marker, bullet.trailing_indent, bullet.text = line:match("^(%s*)([%*%-%+])(%s+)(.*)")
    if not bullet.marker then
        -- Check ordered
        bullet.indent, bullet.marker, bullet.delimiter, bullet.trailing_indent, bullet.text = line:match("^(%s*)(%d+)([%)%.])(%s+)(.*)")
        bullet.type = "ordered_list"
    else
        bullet.delimiter = ""
        bullet.type = "unordered_list"
    end

    -- Didn't find marker at all, must not be a bullet
    if not bullet.marker then
        return nil
    end

    -- Test for checkbox, too hard to do above
    local checkbox = bullet.text:match("^%[([%sx])%]")
    if checkbox then
        bullet.checkbox = {}
        bullet.checkbox.checked = checkbox == "x" and true or false
        bullet.text = bullet.text:sub(5)
    end

    bullet.indent = #bullet.indent
    bullet.trailing_indent = #bullet.trailing_indent
    bullet.start = bullet_line

    -- Iterate down to find bottom of bullet and if it has children

    local line_count = vim.api.nvim_buf_line_count(0)
    local iter = bullet.start + 1 -- start one past end if at last line [1]
    while true do
        local indent = vim.fn.indent(iter)

        -- Test for children
        -- test for having children and larger indent first to prevent regex
        if not bullet.has_children and indent >= bullet.indent + vim.o.shiftwidth then
            local child = vim.fn.getline(iter)
            if child:match(regex.unordered_list) or child:match(regex.ordered_list) then
                bullet.has_children = true
            end
        end

        -- Test for end of bullet
        if indent <= bullet.indent then
            bullet.stop = iter - 1
            break
        end

        -- Last line will always be end
        if iter >= line_count then
            -- [1] checked for being above here
            bullet.stop = line_count
            break
        end

        iter = iter + 1
    end

    -- Try to find parent bullet
    -- Might be too intensive to do the recursive if too deep in the tree
    if bullet.indent > 0 then
        local section = find_header_or_list(bullet.start - 1)
        while true do
            if not section or not section.type or not section.type:match("list") then
                -- Can't find parent even though there is supposed to be one
                break
            elseif vim.fn.indent(section.line) < bullet.indent then
                -- Found parent at lower indentation level
                bullet.parent = parse_bullet(section.line)
                break
            else
                -- Sibling bullet, find next bullet
                section = find_header_or_list(section.line - 1)
            end
        end
    end
    return bullet
end

local function parse_header(line_num)
    local line = vim.fn.getline(line_num)
    local setex_line = vim.fn.getline(line_num + 1)
    local header = {}

    local iter
    if line:match(regex.atx_header) then
        header.start = line_num
        iter = line_num + 1
    elseif setex_line:match(regex.setex_line_header) or setex_line:match(regex.setex_equals_header) then
        header.start = line_num
        iter = line_num + 2
    else
        -- Not a header
        return nil
    end

    -- iterate down to find bottom
    local line_count = vim.api.nvim_buf_line_count(0)
    while true do
        local line = vim.fn.getline(iter)
        if line:match(regex.atx_header) then
            header.stop = iter - 1
            break
        elseif line:match(regex.setex_equals_header) or line:match(regex.setex_line_header) then
            header.stop = iter - 2
            break
        elseif iter == line_count then
            header.stop = iter
            break
        end
        iter = iter + 1
    end
    return header
end

-- Pressing backspace in insert mode calls this function.
-- Removes auto-inserted list markers
function M.backspace()

    -- if beginning of line is list marker, delete it
    -- else normal backspace
    local cursor = vim.api.nvim_win_get_cursor(0)
    local folded, line
    if vim.fn.foldclosed(cursor[1] - 1) ~= -1 then
        folded = true
        line = vim.fn.foldclosed(cursor[1] - 1)
    else
        line = cursor[1] - 1
    end

    -- The bullet above to extract indentation level
    local bullet = parse_bullet(line)
    local indent_length = bullet.indent + #bullet.marker + bullet.trailing_indent + #bullet.delimiter
    if bullet.checkbox then
        indent_length = indent_length + 4
    end

    local newline
    if folded then
        newline = string.rep(" ", indent_length - 2) .. "a"
    else
        -- TODO: reorder list when deleting ordered bullet
        -- Need to append a letter since the backspace is handled normally after this function
        newline = string.rep(" ", indent_length) .. "a"
    end

    vim.fn.setline(".", newline)
    vim.api.nvim_win_set_cursor(0, {cursor[1], 10000})
end


-- Responsible for auto-inserting new bullet points
local function newline(insert_line, folded)
    local bullet_above, bullet_below

    if folded then
        bullet_above = parse_bullet(vim.fn.foldclosed(insert_line))
        bullet_below = parse_bullet(insert_line + 1)
    else
        bullet_above = parse_bullet(insert_line)
        bullet_below = parse_bullet(insert_line + 1)
    end

    if bullet_above then
        -- remove bullet and insert new line if the bullet is empty
        if #bullet_above.text == 0 then
            vim.cmd("startinsert")
            vim.api.nvim_buf_set_lines(0, insert_line-1, insert_line, true, {"",""})
            vim.api.nvim_win_set_cursor(0,{insert_line+1, 0})
            return
        end

        -- Use the properties of the bullet below if its indent is higher than the one above.
        local bullet
        if bullet_below and bullet_below.indent > bullet_above.indent then
            bullet = bullet_below
        else
            bullet = bullet_above
        end

        local indent = string.rep(" ", bullet.indent)
        local marker = bullet.marker
        local delimiter = bullet.delimiter
        local trailing_indent = string.rep(" ", bullet.trailing_indent)

        -- Use checkbox of the above bullet if they are equally indented
        local checkbox
        if bullet_above and bullet_below and bullet_above.indent == bullet_below.indent then
            checkbox = bullet_above.checkbox and "[ ] " or ""
        else
            checkbox = bullet.checkbox and "[ ] " or ""
        end

        if tonumber(marker) then
            marker = marker + 1
            -- TODO: reoder list if there are other bullets below
            --other_bullets = parse_list(bullet.start)
            --for _, bullet_line in pairs(other_bullets) do
            --    local incremented = vim.fn.getline(bullet_line):sub
        end

        local new_line = indent .. marker .. delimiter .. trailing_indent .. checkbox
        vim.cmd("startinsert")
        vim.fn.append(insert_line, new_line)
        vim.api.nvim_win_set_cursor(0,{insert_line+1, 1000000})
        should_run_callback = true
    elseif folded then
        vim.cmd("startinsert")
        vim.fn.append(insert_line, "")
        vim.api.nvim_win_set_cursor(0,{insert_line+1, 0})
    else
        -- Insert line normally
        vim.cmd("startinsert")
        vim.fn.append(insert_line, "")
        vim.api.nvim_win_set_cursor(0,{insert_line+1, 1000000})
    end
end

function M.new_line_above()
    local insert_line = vim.fn.line(".")
    local folded

    if vim.fn.foldclosed(insert_line - 1) > 0 then
        insert_line = vim.fn.foldclosedend(insert_line - 1)
        folded = true
    else
        insert_line = insert_line - 1
    end

    newline(insert_line, folded)
end

function M.new_line_below()
    local insert_line = vim.fn.line(".")
    local folded

    local bullet = parse_bullet(insert_line)

    if vim.fn.mode() == "i" then
        local column = vim.api.nvim_win_get_cursor(0)[2] + 1
        local line = vim.api.nvim_get_current_line()

        -- Normal return if in the middle of a line, or there is no bullet
        if column < #line or not bullet then
            key = vim.api.nvim_replace_termcodes("<CR>", true, false, true)
            vim.api.nvim_feedkeys(key, "n", true)
            return
        end
    else
        if vim.fn.foldclosed(".") > 0 then
            insert_line = vim.fn.foldclosedend(".")
            folded = true
        elseif not bullet then
            vim.api.nvim_feedkeys("o", "n", true)
            return
        end
    end

    newline(insert_line, folded)
end

-- Pressing tab in insert mode calls this function
-- Indents auto-inserted bullet if the line is still empty
-- Jumps between empty fields in links
function M.jump()
    local cursor = vim.api.nvim_win_get_cursor(0)

    -- Check if bullet
    local bullet = parse_bullet(cursor[1])

    -- Find if inside link
    local link = find_link_under_cursor()

    if bullet and (#bullet.text == 0 or bullet.text:match("%s*%[.%]")) then
        -- empty bullet
        local line = string.rep(" ", bullet.indent + vim.o.shiftwidth)
        local checkbox = bullet.checkbox and "[ ] " or ""
        line = line .. bullet.marker .. bullet.delimiter .. string.rep(" ", bullet.trailing_indent) .. checkbox
        vim.api.nvim_buf_set_lines(0, cursor[1] - 1, cursor[1], true, {line})
        vim.api.nvim_win_set_cursor(0,{cursor[1], 1000000})
    elseif link and cursor[2] >= link.start and cursor[2] <= link.stop then
        --error(vim.inspect({cursor,link}))
        local relative_position = cursor[2] - link.start + 1
        local _, end_bracket = link.link:find("%[%]")
        local start_parenthesis = link.link:find("%(%)")
        --error(vim.inspect({end_bracket, relative_position}))
        if end_bracket and relative_position > end_bracket then
            -- Switch to empty brackets from parentheses
            vim.api.nvim_win_set_cursor(0, {cursor[1], link.start})
        elseif start_parenthesis and relative_position < start_parenthesis then
            --error(vim.inspect(link))
            -- Switch to empty parentheses from brackets
            vim.api.nvim_win_set_cursor(0, {cursor[1], link.stop-1})
        else
            -- go to end
            --if link_stop == #line then
            --    -- insert a space at the end for convenience if at the end of the line
            --    vim.cmd("startinsert!")
            --    vim.api.nvim_feedkeys(" ", "n", true)
            --else
                vim.api.nvim_win_set_cursor(0, {cursor[1], link.stop})
            --end
        end
    else
        -- normal tab
        local key = vim.api.nvim_replace_termcodes("<TAB>", true, false, true)
        vim.api.nvim_feedkeys(key, 'n', true)
    end
end

-- Pressing tab in normal mode calls this function
-- Folds by bullets if cursor at one, else folds by headers
function M.fold()
    local line_num = vim.fn.line('.')

    -- Fold is closed, delete it and return
    if vim.fn.foldclosed(line_num) > 0 then
        vim.cmd("norm zd")
        return
    end

    local iter = line_num
    while true do
        -- iterates up until it finds something foldable, or the beginning of the file
        local section = find_header_or_list(iter)

        if not section then
            break
        end

        if section.type:match("list") then
            local bullet = parse_bullet(section.line)

            if bullet and (line_num < bullet.start or line_num > bullet.stop) then
                -- cursor isn't inside the list
                bullet = nil
            end

            local fold_start, fold_stop = nil, nil
            if bullet and bullet.has_children then
                -- Will fold the bullet and its children
                fold_start = bullet.start
                fold_stop = bullet.stop
            elseif bullet and bullet.parent then
                -- Bullet doesn't have any children, assume that you wanted to fold the parent
                fold_start = bullet.parent.start
                fold_stop = bullet.parent.stop
            end

            --error(vim.inspect({fold_start, fold_stop, bullet}))
            -- if fold_start is still nil, it's a bullet that can't be folded
            if fold_start then
                vim.cmd("silent! norm zd") -- delete any remnant folds
                vim.cmd(string.format("%d,%dfold",fold_start, fold_stop))
                break
            end
        elseif section.type:match("header") then
            -- if header, fold it entire thing
            local header = parse_header(section.line)
            vim.cmd("silent! norm zd") -- delete any remnant folds
            vim.cmd(string.format("%d,%dfold", header.start, header.stop))
            break
        end
        iter = section.line - 1
    end
end

-- Pressing return in normal mode will call this function.
-- Follows links
function M.follow_link()
    local word = find_word_under_cursor()
    local link = find_link_under_cursor() -- matches []() links only
    if link and link.url then
        if link.url:match("^https?://") then
            -- a link
            vim.ui.open(link.url)
        else
            -- a file path/anchor

            -- check if path contains a line number e.g. file.md#L10
            local line_number = link.url:match("#L(%d+)$") or ""
            if line_number ~= "" then
                -- remove line number info if it exists
                line_number = "+" .. line_number .. " "
                link.url = link.url:gsub("#L%d+$", "")
            end

            -- check if path contains an anchor e.g. file.md#my-header or just #my-header
            local anchor = link.url:match("#(.+)$") or ""
            if anchor ~= "" then
                link.url = link.url:gsub("#.+$", "")
            end

            if link.url ~= "" then
                -- try to follow path
                local ok, _ = pcall(function ()
                    if string.match(link.url, "^[~/]") then
                        -- an absolute path
                        vim.cmd("e " .. line_number .. link.url)
                    else
                        -- a relative path
                        vim.cmd("e " .. line_number .. vim.fn.expand('%:p:h') .. '/' .. link.url)
                    end
                end)

                if not ok then
                    vim.notify("Invalid link: " .. link.url, vim.log.levels.ERROR)
                end
            end

            if anchor ~= "" then
                vim.fn.search("^#* "..anchor:gsub("-", "[%- ]"))
            end

        end
    elseif word then
        if word.text:match("^https?://") then
            -- Bare url i.e without link syntax
            vim.ui.open(link.url)
        end
    end
end


-- Takes the word under the cursor and puts it in the appropriate spot in a link.
-- If no word is under the cursor, insert the link syntax
function M.create_link()
    local line = vim.fn.getline(".")
    local cursor = vim.api.nvim_win_get_cursor(0)
    local mode = vim.fn.mode(".")

    local new_line, new_cursor_pos
    if mode == "i" or mode == "ic" or mode == "n" then
        local word = find_word_under_cursor()
        if word and (word.text:match("/") or vim.fn.filereadable(word.text) == 1) then
            -- convert an url to a link
            new_line = line:sub(1,word.start-1) .. "[]"
            new_cursor_pos = #new_line
            new_line = new_line .. "(" .. word.text .. ")" .. line:sub(word.stop+1)
        elseif word then
            -- convert word to a link
            new_line = line:sub(1,word.start-1) .. "[" .. word.text .. "]()"
            new_cursor_pos = #new_line
            new_line = new_line .. line:sub(word.stop+1)
        else
            -- just insert link syntax
            new_line = line:sub(1,cursor[2]) .. "[]"
            new_cursor_pos = #new_line
            new_line = new_line .. "()" .. line:sub(cursor[2] + 1)
        end
    elseif mode == "v" or mode == "\22" then
        -- \22 is visual block mode on mine, might be wrong for others.
        vim.cmd(":normal! ") -- Need to return to normal mode to set the below marks
        local start = vim.fn.getpos("'<")
        local stop = vim.fn.getpos("'>")

        -- Don't do anything if the visual selection spans multiple lines
        if start[2] ~= stop[2] then
            return
        else
            start = start[3]
            stop = stop[3]
        end

        local selection = line:sub(start, stop)
        if selection:match("/") or vim.fn.filereadable(selection) == 1 then
            new_line = line:sub(1,start-1) .. "[]"
            new_cursor_pos = #new_line
            new_line = new_line .. "(" .. selection .. ")" .. line:sub(stop+1)
        else
            new_line = line:sub(1,start-1) .. "[" .. selection .. "]()"
            new_cursor_pos = #new_line
            new_line = new_line .. line:sub(stop+1)
        end
    else
        return
    end

    vim.fn.setline(".", new_line)
    vim.fn.setpos(".", {0, cursor[1], new_cursor_pos, 0})
    vim.cmd("startinsert")
end

-- Given the line number of one of the bullets in a list,
-- returns a table with the position of all the siblings in the list
--function renumber_ordered_list(line_num)
--    local list = {}
--    local list_indent = vim.fn.indent(line_num)
--
--    -- iterate up
--    local iter = line_num - 1
--    while true do
--        local line = vim.fn.getline(iter)
--        local indent = vim.fn.indent(iter)
--        if indent == list_indent and (line:match(regex.ordered_list) or line:match(regex.unordered_list)) then
--            -- Found bullet
--            list:insert(1, iter)
--        elseif indent < list_indent then
--            -- Top of list
--            break
--        end
--        iter = iter -1
--    end
--
--    -- insert line_num bullet
--    list:insert(line_num)
--
--    -- iterate down
--    local iter = line_num + 1
--    while true do
--        local line = vim.fn.getline(iter)
--        local indent = vim.fn.indent(iter)
--        if indent == list_indent and (line:match(regex.ordered_list) or line:match(regex.unordered_list)) then
--            -- Found bullet
--            list:insert(iter)
--        elseif indent < list_indent then
--            -- Top of list
--            break
--        end
--        iter = iter -1
--    end
--
--    return list
--end

-- Pressing C-c calls this function
-- Iterates through todo list for all list types
-- From none -> unmarked -> marked - none
-- TODO: visual selection, mark and unmark, not remove
function M.toggle_checkbox()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line = vim.api.nvim_get_current_line()
    local bullet = parse_bullet(cursor[1])

    if not bullet then
        return
    end

    -- Fill checkbox
    if bullet.checkbox and not bullet.checkbox.checked then
        if #bullet.text == 0 then
            -- if there is no text the user probably wants to remove the checkbox
            -- since it's not returning here, it will hit the if below, and get replaced again
            line = line:gsub("%[%s%]","[x]")
            bullet.checkbox.checked = true
        else
            -- else fill it
            line = line:gsub("%[%s]","[x]")
            vim.api.nvim_buf_set_lines(0, cursor[1]-1, cursor[1], 1, {line})
            return
        end

    end

    -- Return to normal list item
    if bullet.checkbox and bullet.checkbox.checked then
        line = line:gsub("%s%[x%]","")
        vim.api.nvim_buf_set_lines(0, cursor[1]-1, cursor[1], 1, {line})

        -- If the cursor was in the bullet text, move it backwards
        local checkbox = bullet.checkbox and 4 or 0
        local text_start = bullet.indent + #bullet.marker + #bullet.delimiter + checkbox
        if cursor[2] + 1 > text_start then
            -- removing before cursor should move the cursor too
            vim.api.nvim_win_set_cursor(0, {cursor[1],cursor[2] - 4})
        end
        return
    end

    -- Convert list item to checkbox
    if not bullet.checkbox then
        local trailing_indent = string.rep(" ", bullet.trailing_indent)
        if #bullet.text == 0 and bullet.trailing_indent == 0 then
            trailing_indent = " "
        end

        line = string.rep(" ", bullet.indent) .. bullet.marker .. bullet.delimiter .. " [ ]" .. trailing_indent .. bullet.text
        vim.api.nvim_buf_set_lines(0, cursor[1]-1, cursor[1], 1, {line})

        -- if the cursor was in the bullet text, move it forwards
        local text_start = bullet.indent + #bullet.marker + #bullet.delimiter
        if cursor[2] + 1 == text_start + 1 then
            -- when in insert mode and you press C-c without indenting
            vim.api.nvim_win_set_cursor(0, {cursor[1],cursor[2] + 5})
        elseif cursor[2] + 1 > text_start then
            vim.api.nvim_win_set_cursor(0, {cursor[1],cursor[2] + 4})
        end
        return
    end
end

--function M.visual_convert_to_link()
--    local cursor = vim.api.nvim_win_get_cursor()
--    local start = vim.api.nvim_buf_get_mark("<")
--    local stop = vim.api.nvim_buf_get_mark(">")
--    local line = vim.api.nvim_get_current_line()
--    local segment = line:sub(start, stop)
--    local before = line:sub(0,stop)
--    local after = line:sub(stop)
--
--    if segment:match("%.*?%/*?") then
--        -- Is probably url
--        local newline = before .. "[](" .. segment .. ")" .. after
--    elseif #segment > 0 then
--        local newline = before .. "[" .. segment .. "]()" .. after
--    else
--        cursor[2] = cursor[2] + 1
--        local newline = before .. "[]()"
--    end
--end

--function insert_convert_to_link()
--    local cursor = vim.api.nvim_win_get_cursor(0)
--    local line =
--    vim.cmd("norm hviW")
--    M.visual_convert_to_link()
--end

return M
