local M = {}

-- Default configuration
M.config = {
  width = 40,
  side = "right",
  auto_close = false,
  border = "single",
  title = "Search Sidebar"
}

-- Store our sidebar buffer number
M.sidebar_bufnr = nil

-- Store our sidebar window ID
M.sidebar_win_id = nil

-- Store search state
M.search = {
  query = "",
  include = "",  -- Will be set to current working directory
  exclude = ""
}

-- Store search results
M.results = {}

-- Parse search results into a structured format
local function parse_search_results(output)
  local results = {}
  local current_file = nil
  
  for line in output:gmatch("[^\r\n]+") do
    -- Check if this is a file path line (first match in a file)
    local file_path, line_num, content = line:match("^(.+):(%d+):(.*)$")
    
    if file_path and line_num then
      -- Check if this is a new file or existing file
      if not results[file_path] then
        results[file_path] = {
          path = file_path,
          hits = {}
        }
      end
      
      -- Add the hit to the file
      table.insert(results[file_path].hits, {
        line_num = tonumber(line_num),
        content = content:gsub("^%s*", "")  -- Remove leading whitespace
      })
    end
  end
  
  return results
end

-- Fixed search function to prevent modifiable error
local function perform_search()
  -- If search query is empty, don't search
  if M.search.query == "" then
    M.results = {}
    return M.results
  end
  
  -- Get search directory (include)
  local dir = M.search.include
  if dir == "" then
    dir = vim.fn.getcwd()
  end
  
  -- Use ripgrep if available, otherwise fall back to grep
  local cmd
  if vim.fn.executable('rg') == 1 then
    cmd = string.format('rg --line-number --no-heading "%s" "%s"', M.search.query, dir)
    if M.search.exclude ~= "" then
      cmd = cmd .. string.format(' --glob "!%s"', M.search.exclude)
    end
  else
    cmd = string.format('grep -r -n "%s" "%s"', M.search.query, dir)
    if M.search.exclude ~= "" then
      cmd = cmd .. string.format(' --exclude="%s"', M.search.exclude)
    end
  end
  
  -- Execute search with error handling
  local output = vim.fn.system(cmd)
  if vim.v.shell_error > 1 then
    vim.api.nvim_err_writeln("Search error: " .. output)
    return {}
  end
  
  -- Parse the results with error handling
  local success, results = pcall(parse_search_results, output)
  if success then
    M.results = results
  else
    vim.api.nvim_err_writeln("Error parsing results: " .. tostring(results))
    M.results = {}
  end
  
  return M.results
end

-- Setup syntax highlighting for the sidebar
local function setup_syntax()
  if not M.sidebar_bufnr or not vim.api.nvim_buf_is_valid(M.sidebar_bufnr) then
    return
  end
  
  -- Set the filetype first to prevent interference
  pcall(vim.api.nvim_buf_set_option, M.sidebar_bufnr, 'filetype', 'sidebar')
  
  -- Define highlight groups
  vim.api.nvim_set_hl(0, 'SidebarTitle', { fg = '#ff9e64', bold = true })
  vim.api.nvim_set_hl(0, 'SidebarLabel', { fg = '#7dcfff' })
  vim.api.nvim_set_hl(0, 'SidebarValue', { fg = '#9ece6a' })
  vim.api.nvim_set_hl(0, 'SidebarInstruction', { fg = '#bb9af7', italic = true })
  vim.api.nvim_set_hl(0, 'SidebarSearchKey', { fg = '#f7768e', bold = true })
  vim.api.nvim_set_hl(0, 'SidebarBorder', { fg = '#565f89' })
  vim.api.nvim_set_hl(0, 'SidebarResults', { fg = '#ff9e64', bold = true })
  vim.api.nvim_set_hl(0, 'SidebarFile', { fg = '#bb9af7', bold = true })
  vim.api.nvim_set_hl(0, 'SidebarLineNum', { fg = '#565f89' })
  vim.api.nvim_set_hl(0, 'SidebarMatch', { fg = '#f7768e', bold = true })
  
  -- Apply syntax matches with more specific patterns
  local syntax_cmds = [[
    syntax clear
    
    " Border and header
    syntax match SidebarBorder /^[-=]\+$/
    syntax match SidebarBorder /^.*Search Sidebar.*$/
    syntax match SidebarTitle /Search Sidebar/ contained containedin=SidebarBorder
    
    " Input field labels
    syntax match SidebarLabel /^Search query:/
    syntax match SidebarLabel /^Include files:/
    syntax match SidebarLabel /^Exclude files:/
    
    " Input field values (match only after the colon)
    syntax match SidebarValue /\(^Search query:\s\+\)\@<=.*$/
    syntax match SidebarValue /\(^Include files:\s\+\)\@<=.*$/
    syntax match SidebarValue /\(^Exclude files:\s\+\)\@<=.*$/
    
    " Instructions
    syntax match SidebarInstruction /^Press i to edit.*$/
    syntax match SidebarInstruction /^Press q to close.*$/
    
    " Search key highlight
    syntax match SidebarInstruction /^Press \zsearch/ contains=SidebarSearchKey
    
    " Results section
    syntax match SidebarResults /^.*Search Results.*$/
    
    " File paths in results
    syntax match SidebarFile /^→ .*$/
    
    " Line numbers in results
    syntax match SidebarLineNum /^\s\+\d\+:/
    
    " Match content (only the actual text after line number)
    syntax match SidebarMatch /\(^\s\+\d\+:\s*\)\@<=.*$/
  ]]
  
  vim.cmd(syntax_cmds)
end

-- Format search results for display
local function format_search_results()
  local lines = {}
  
  -- Check if we have results
  local has_results = false
  for _ in pairs(M.results) do
    has_results = true
    break
  end
  
  if not has_results then
    if M.search.query ~= "" then
      table.insert(lines, "No results found")
    end
    return lines
  end
  
  -- Format results by file
  for file_path, file_data in pairs(M.results) do
    -- Add file path
    table.insert(lines, "→ " .. file_path)
    
    -- Add each hit
    for _, hit in ipairs(file_data.hits) do
      table.insert(lines, "  " .. hit.line_num .. ": " .. hit.content)
    end
    
    -- Add a separator between files
    table.insert(lines, string.rep("-", M.config.width))
  end
  
  return lines
end

-- Update the sidebar content
local function update_sidebar_content()
  if not M.sidebar_bufnr or not vim.api.nvim_buf_is_valid(M.sidebar_bufnr) then
    return
  end
  
  -- Set "Include files" to current directory if it's empty
  if M.search.include == "" then
    M.search.include = vim.fn.getcwd()
  end
  
  local width = M.config.width  -- Account for padding
  local header_padding = math.floor((width / 2)) - 8 -- Center "Search Sidebar" text
  local header = string.rep("=", header_padding) .. " Search Sidebar " .. string.rep("=", header_padding)
  local divider = string.rep("=", header_padding) .. " Search Results " .. string.rep("=", header_padding)

  -- Make buffer modifiable with robust error handling
  local mod_ok = pcall(vim.api.nvim_buf_set_option, M.sidebar_bufnr, 'modifiable', true)
  if not mod_ok then
    vim.api.nvim_err_writeln("Failed to set buffer modifiable")
    return
  end
  
  local lines = {
    header,
    "",
    "Search query: " .. M.search.query,
    "Include files: " .. M.search.include,
    "Exclude files: " .. M.search.exclude,
    "",
    "Press i to edit field",
    "Press s to search",  
    "Press q to close search",
    divider,
  }
  
  -- Add search results
  local result_lines = format_search_results()
  for _, line in ipairs(result_lines) do
    table.insert(lines, line)
  end
  
  -- Set the content with error handling
  local set_ok = pcall(vim.api.nvim_buf_set_lines, M.sidebar_bufnr, 0, -1, false, lines)
  if not set_ok then
    vim.api.nvim_err_writeln("Failed to update buffer content")
    -- Try to restore modifiable state
    pcall(vim.api.nvim_buf_set_option, M.sidebar_bufnr, 'modifiable', false)
    return
  end
  
  -- Make buffer non-modifiable again
  pcall(vim.api.nvim_buf_set_option, M.sidebar_bufnr, 'modifiable', false)
  
  -- Apply syntax highlighting
  setup_syntax()
end

-- Handle editing of a field
local function edit_field(field_name)
  local prompt = "Enter " .. field_name .. ": "
  local current_value = M.search[field_name]
  
  -- Special handling for include field - use file browser
  if field_name == "include" and current_value == "" then
    current_value = vim.fn.getcwd()
  end
  
  vim.ui.input({ prompt = prompt, default = current_value }, function(input)
    if input ~= nil then -- not cancelled
      M.search[field_name] = input
      update_sidebar_content()
    end
  end)
end

-- Open a file at a specific line with focus retention
local function open_file_at_line(file_path, line_num)
  -- Check if the file exists
  if vim.fn.filereadable(file_path) == 0 then
    vim.api.nvim_err_writeln("File not found: " .. file_path)
    return
  end
  
  -- Find a non-sidebar window to use, or create one
  local target_win
  local current_wins = vim.api.nvim_list_wins()
  for _, win_id in ipairs(current_wins) do
    -- Skip the sidebar window and invalid windows
    if win_id ~= M.sidebar_win_id and vim.api.nvim_win_is_valid(win_id) then
      -- Found a suitable window
      target_win = win_id
      break
    end
  end
  
  -- If no suitable window found, create a split
  if not target_win then
    vim.cmd("wincmd v") -- Vertical split
    target_win = vim.api.nvim_get_current_win()
  end
  
  -- Switch to the target window
  vim.api.nvim_set_current_win(target_win)
  
  -- Open the file in this window
  vim.cmd("edit " .. vim.fn.fnameescape(file_path))
  
  -- Go to the specific line
  if line_num then
    -- Use win_set_cursor with protected call
    pcall(vim.api.nvim_win_set_cursor, target_win, {line_num, 0})
    
    -- Center the view
    vim.cmd("normal! zz")
    
    -- Highlight the line briefly
    local current_cursorline = vim.opt.cursorline:get()
    vim.opt.cursorline = true
    vim.defer_fn(function()
      if vim.api.nvim_win_is_valid(target_win) then
        vim.api.nvim_set_option_value('cursorline', current_cursorline, { win = target_win })
      end
    end, 1000)
  end
  
  -- Forcefully set focus to this window and away from sidebar
  vim.api.nvim_set_current_win(target_win)
  
  -- Prevent jumping back to sidebar by using defer_fn with higher priority
  vim.defer_fn(function()
    if vim.api.nvim_win_is_valid(target_win) then
      vim.api.nvim_set_current_win(target_win)
    end
  end, 10)
end

-- Handle Enter key press on search results
local function handle_result_enter()
  -- Get current line
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local content = vim.api.nvim_buf_get_lines(M.sidebar_bufnr, line - 1, line, false)[1]
  
  -- If this is a file path line
  if content:match("^→ (.*)") then
    local file_path = content:match("^→ (.*)")
    open_file_at_line(file_path)
    return true -- Return true to indicate navigation happened
  end
  
  -- If this is a hit line
  local line_num_match = content:match("^%s*(%d+):")
  if line_num_match then
    -- Find the associated file
    -- Go up until we find a file path line
    local file_path = nil
    for i = line - 1, 1, -1 do
      local prev_line = vim.api.nvim_buf_get_lines(M.sidebar_bufnr, i - 1, i, false)[1]
      if prev_line:match("^→ (.*)") then
        file_path = prev_line:match("^→ (.*)")
        break
      end
    end
    
    if file_path then
      open_file_at_line(file_path, tonumber(line_num_match))
      return true -- Return true to indicate navigation happened
    end
  end
  
  return false -- Return false if no navigation happened
end

-- Create and setup the sidebar buffer
function M.create_sidebar_buffer()
  -- Create a new buffer for the sidebar
  local bufnr = vim.api.nvim_create_buf(false, true)
  
  -- Set buffer options
  pcall(vim.api.nvim_buf_set_option, bufnr, 'buftype', 'nofile')
  pcall(vim.api.nvim_buf_set_option, bufnr, 'swapfile', false)
  pcall(vim.api.nvim_buf_set_option, bufnr, 'buflisted', false)
  pcall(vim.api.nvim_buf_set_option, bufnr, 'filetype', 'sidebar')
  
  -- Store the buffer number
  M.sidebar_bufnr = bufnr
  
  -- Ensure Include files has the current directory
  if M.search.include == "" then
    M.search.include = vim.fn.getcwd()
  end
  
  -- Update the initial content
  update_sidebar_content()
  
  -- Add keymaps for the sidebar
  -- Close sidebar with 'q'
  vim.keymap.set('n', 'q', function()
    if M.drawer then
      M.drawer.toggle()
    end
  end, { buffer = bufnr, noremap = true, silent = true })
  
  -- Edit field with 'i'
  vim.keymap.set('n', 'i', function()
    local line = vim.api.nvim_win_get_cursor(0)[1]
    
    if line == 3 then
      -- Search query field
      edit_field("query")
    elseif line == 4 then
      -- Include files field
      edit_field("include")
    elseif line == 5 then
      -- Exclude files field
      edit_field("exclude")
    end
  end, { buffer = bufnr, noremap = true, silent = true })
  
  -- Improved keymap for search that ensures buffer is modifiable
  vim.keymap.set('n', 's', function()
    -- First make sure the buffer is modifiable
    if M.is_valid_buffer(M.sidebar_bufnr) then
      -- Run the search
      local results = perform_search()
      
      -- Schedule the update to avoid race conditions
      vim.schedule(function()
        -- Ensure buffer is still valid before updating
        if M.is_valid_buffer(M.sidebar_bufnr) then
          -- Make modifiable with pcall for safety
          pcall(vim.api.nvim_buf_set_option, M.sidebar_bufnr, 'modifiable', true)
          -- Update content
          update_sidebar_content()
        end
      end)
    end
  end, { buffer = bufnr, noremap = true, silent = true })
  
  -- Add Enter key for editing inputs and opening files
  vim.keymap.set('n', '<CR>', function()
    local line = vim.api.nvim_win_get_cursor(0)[1]
    
    if line == 3 then
      -- Search query field
      edit_field("query")
    elseif line == 4 then
      -- Include files field
      edit_field("include")
    elseif line == 5 then
      -- Exclude files field
    elseif line > 10 then
      -- This is likely a search result - try to open the file
      local navigated = handle_result_enter()
      -- If we successfully navigated, don't perform any further actions
      if navigated then
        return
      end
    end
  end, { buffer = bufnr, noremap = true, silent = true })
  
  return bufnr
end

-- Safe function to check if a buffer exists and is valid
function M.is_valid_buffer(bufnr)
  return bufnr and pcall(vim.api.nvim_buf_is_valid, bufnr) and vim.api.nvim_buf_is_valid(bufnr)
end

-- Safe function to check if a window exists and is valid
function M.is_valid_window(winid)
  return winid and pcall(vim.api.nvim_win_is_valid, winid) and vim.api.nvim_win_is_valid(winid)
end

-- Function to ensure sidebar window shows our sidebar buffer
function M.force_sidebar_buffer()
  -- Only proceed if we have a valid sidebar window
  if not M.is_valid_window(M.sidebar_win_id) then
    return false
  end
  
  -- Ensure we have a valid sidebar buffer
  if not M.is_valid_buffer(M.sidebar_bufnr) then
    -- Create a new sidebar buffer if needed
    M.sidebar_bufnr = M.create_sidebar_buffer()
  end
  
  -- Check if the window is showing our buffer
  local success, current_buf = pcall(vim.api.nvim_win_get_buf, M.sidebar_win_id)
  if success and current_buf ~= M.sidebar_bufnr then
    -- If not, set it to our buffer
    pcall(vim.api.nvim_win_set_buf, M.sidebar_win_id, M.sidebar_bufnr)
    return true
  end
  
  return false
end

-- Setup function to initialize with user configuration
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  
  -- Set initial include files to current directory if not specified
  if M.search.include == "" then
    M.search.include = vim.fn.getcwd()
  end
  
  -- Create the sidebar buffer once during setup
  M.sidebar_bufnr = M.create_sidebar_buffer()
  
  -- Set up commands after configuration is loaded
  vim.api.nvim_create_user_command('SidebarToggle', function()
    require('sidebar').toggle()
  end, {})
  
  -- Create autocmd group for sidebar protection
  local augroup = vim.api.nvim_create_augroup("SidebarProtection", { clear = true })
  
  -- Use BufEnter to check if a buffer is trying to enter the sidebar window
  vim.api.nvim_create_autocmd("BufEnter", {
    group = augroup,
    pattern = "*",
    callback = function()
      -- Check if our sidebar window is valid
      if M.is_valid_window(M.sidebar_win_id) then
        -- Check if the current window is our sidebar window
        local current_win = vim.api.nvim_get_current_win()
        if current_win == M.sidebar_win_id then
          -- If we're in the sidebar window, ensure it shows our buffer
          M.force_sidebar_buffer()
        end
      end
    end
  })
  
  -- Add WinEnter to catch window switching
  vim.api.nvim_create_autocmd("WinEnter", {
    group = augroup,
    pattern = "*",
    callback = function()
      -- Check if our sidebar window is valid
      if M.is_valid_window(M.sidebar_win_id) then
        -- Check if the current window is our sidebar window
        local current_win = vim.api.nvim_get_current_win()
        if current_win == M.sidebar_win_id then
          -- If we're in the sidebar window, ensure it shows our buffer
          M.force_sidebar_buffer()
        end
      end
    end
  })
end

-- Function to toggle the sidebar
function M.toggle()
  local drawer = require('nvim-drawer')
  
  -- Ensure we have a sidebar buffer
  if not M.is_valid_buffer(M.sidebar_bufnr) then
    M.sidebar_bufnr = M.create_sidebar_buffer()
  end
  
  -- Check and update current working directory
  if M.search.include == "" then
    M.search.include = vim.fn.getcwd()
  end
  
  if not M.drawer then
    M.drawer = drawer.create_drawer({
      size = M.config.width,
      position = M.config.side,
      title = M.config.title,
      should_reuse_previous_bufnr = true,
      should_close_on_bufwipeout = false,
      
      on_did_create_buffer = function()
        -- Get the current window
        local win = vim.api.nvim_get_current_win()
        
        -- Set our sidebar buffer in this window
        pcall(vim.api.nvim_win_set_buf, win, M.sidebar_bufnr)
        
        -- Mark this window as our sidebar window
        M.sidebar_win_id = win
        
        -- Update syntax
        vim.schedule(function()
          setup_syntax()
        end)
      end,
      
      on_did_open = function()
        -- Configure local window options
        vim.opt_local.number = false
        vim.opt_local.relativenumber = false
        vim.opt_local.signcolumn = 'no'
        vim.opt_local.statuscolumn = ''
        vim.opt_local.cursorline = true
        
        -- Lock window settings
        pcall(vim.api.nvim_win_set_option, 0, 'winfixwidth', true)
        pcall(vim.api.nvim_win_set_option, 0, 'winfixheight', true)
        
        -- Set buffer options to discourage switching
        vim.opt_local.bufhidden = 'hide'
        vim.opt_local.buftype = 'nofile'
        
        -- Make sure we're showing the sidebar buffer
        pcall(vim.api.nvim_win_set_buf, 0, M.sidebar_bufnr)
        
        -- Store window ID
        M.sidebar_win_id = vim.api.nvim_get_current_win()
        
        -- Schedule syntax setup to ensure it runs after buffer is fully loaded
        vim.schedule(function()
          update_sidebar_content()
          setup_syntax()
        end)
      end,
      
      on_did_close = function()
        -- Reset sidebar window ID when closed
        M.sidebar_win_id = nil
      end,
    })
  end
  
  -- Safely toggle the drawer
  pcall(function() 
    if M.drawer.focus_or_toggle then
      M.drawer.focus_or_toggle() 
    end
  end)
  
  -- Added: Make sure to update sidebar content when toggling
  vim.schedule(function()
    if M.is_valid_buffer(M.sidebar_bufnr) then
      update_sidebar_content()
    end
  end)
end

return M