-- Initialize the plugin
if vim.g.loaded_sidebar_plugin then
  return
end
vim.g.loaded_sidebar_plugin = true

-- Define the command to toggle the sidebar
vim.api.nvim_create_user_command('SidebarToggle', function()
  require('sidebar').toggle()
end, {})