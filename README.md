# ss.nvim

Search Sidebar

## Installation

Lazy

```vim
{
  {
    "4thwithme/ss.nvim",
    name = "ss.nvim",
    lazy = false,
    dependencies = {
      "mikew/nvim-drawer"
    },
    config = function()
      require("sidebar").setup({
        width = 60,
        side = "right",
        auto_close = false,
        border = "single",
        title = "Search Sidebar",
      })

      vim.keymap.set("n", "<leader>S", "<cmd>SidebarToggle<CR>", { desc = "Toggle Sidebar" })
    end,
  },
}
```

## Usage

Once installed, you can open the sidebar by running the command:

```
:SidebarOpen
```

To close the sidebar, use the command:

```
:SidebarClose
```

The sidebar will display the text 'HELLO' when opened.

## Configuration

You can customize the sidebar's behavior by modifying the settings in `lua/sidebar/config.lua`. This may include key mappings or other options to enhance your experience.

## Example

To quickly toggle the sidebar, you can create a key mapping in your configuration file:

```lua
vim.api.nvim_set_keymap('n', '<leader>S', ':SidebarToggle<CR>', { noremap = true, silent = true })
```

This will allow you to open and close the sidebar using `<leader>S`.
