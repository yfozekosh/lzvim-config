local M = {}

local map = vim.keymap.set

local function clients()
  local ok, result = pcall(vim.lsp.get_clients, { bufnr = 0 })
  if not ok then
    ok, result = pcall(vim.lsp.buf_get_clients, 0)
  end
  if ok and type(result) == "table" then
    return result
  end
  return {}
end

function M.toggle_comment_and_next()
  local mode = vim.fn.mode()
  if mode == "i" then
    vim.cmd("stopinsert")
    pcall(vim.cmd, "normal gcc")
    vim.cmd("normal! j")
    vim.cmd("startinsert")
  elseif mode == "v" or mode == "V" or mode == "\22" then
    local first = vim.fn.line("v")
    local last = vim.fn.line(".")
    vim.cmd("normal! \27")
    if first > last then
      first, last = last, first
    end
    vim.cmd(("normal %dGV%dGgc"):format(first, last))
    vim.cmd("normal! j")
  else
    pcall(vim.cmd, "normal gcc")
    vim.cmd("normal! j")
  end
end

function M.code_action()
  if #clients() > 0 then
    vim.lsp.buf.code_action()
  else
    vim.notify("No LSP client attached", vim.log.levels.WARN)
  end
end

function M.close_others()
  local current = vim.api.nvim_get_current_buf()
  local closed_count = 0

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local buf_ft = vim.bo[buf].filetype
    local is_current = buf == current
    local is_terminal = buf_ft == "terminal"
    local is_explorer = buf_ft == "neo-tree" or buf_ft == "NvimTree"

    if vim.bo[buf].buflisted and not is_current and not is_terminal and not is_explorer then
      vim.cmd("bd! " .. buf)
      closed_count = closed_count + 1
    end
  end

  vim.bo[current].buflisted = true
  vim.cmd("buffer " .. current)

  vim.opt.number = true
  vim.opt.relativenumber = true
  vim.cmd("redrawstatus")
  vim.cmd("redraw")

  local name = vim.fn.expand("%:t")
  if name == "" then
    name = "[No Name]"
  end
  vim.notify("Closed " .. closed_count .. " buffer(s). Still viewing: " .. name, vim.log.levels.INFO)
end

local function diagnostic_goto(next, severity)
  return function()
    local opts = { severity = severity and vim.diagnostic.severity[severity] or nil }
    local count = vim.v.count1
    if vim.diagnostic.jump then
      opts.count = (next and 1 or -1) * count
      opts.float = true
      vim.diagnostic.jump(opts)
      return
    end
    for _ = 1, count do
      if next then
        vim.diagnostic.goto_next(opts)
      else
        vim.diagnostic.goto_prev(opts)
      end
    end
  end
end

local function format()
  if #clients() > 0 then
    vim.lsp.buf.format({ async = true })
  else
    vim.notify("No LSP formatter", vim.log.levels.WARN)
  end
end

function M.setup()
  -- better up/down
  map({ "n", "x" }, "j", "v:count == 0 ? 'gj' : 'j'", { desc = "Down", expr = true, silent = true })
  map({ "n", "x" }, "<Down>", "v:count == 0 ? 'gj' : 'j'", { desc = "Down", expr = true, silent = true })
  map({ "n", "x" }, "k", "v:count == 0 ? 'gk' : 'k'", { desc = "Up", expr = true, silent = true })
  map({ "n", "x" }, "<Up>", "v:count == 0 ? 'gk' : 'k'", { desc = "Up", expr = true, silent = true })

  -- windows
  map("n", "<C-h>", "<C-w>h", { desc = "Go to Left Window", remap = true })
  map("n", "<C-j>", "<C-w>j", { desc = "Go to Lower Window", remap = true })
  map("n", "<C-k>", "<C-w>k", { desc = "Go to Upper Window", remap = true })
  map("n", "<C-l>", "<C-w>l", { desc = "Go to Right Window", remap = true })
  map("n", "<C-Up>", "<cmd>resize +2<cr>", { desc = "Increase Window Height" })
  map("n", "<C-Down>", "<cmd>resize -2<cr>", { desc = "Decrease Window Height" })
  map("n", "<C-Left>", "<cmd>vertical resize -2<cr>", { desc = "Decrease Window Width" })
  map("n", "<C-Right>", "<cmd>vertical resize +2<cr>", { desc = "Increase Window Width" })

  -- move lines
  map("n", "<A-j>", "<cmd>execute 'move .+' . v:count1<cr>==", { desc = "Move Down" })
  map("n", "<A-k>", "<cmd>execute 'move .-' . (v:count1 + 1)<cr>==", { desc = "Move Up" })
  map("i", "<A-j>", "<esc><cmd>m .+1<cr>==gi", { desc = "Move Down" })
  map("i", "<A-k>", "<esc><cmd>m .-2<cr>==gi", { desc = "Move Up" })
  map("v", "<A-j>", ":<C-u>execute \"'<,'>move '>+\" . v:count1<cr>gv=gv", { desc = "Move Down" })
  map("v", "<A-k>", ":<C-u>execute \"'<,'>move '<-\" . (v:count1 + 1)<cr>gv=gv", { desc = "Move Up" })

  -- buffers
  map("n", "<S-h>", "<cmd>bprevious<cr>", { desc = "Prev Buffer" })
  map("n", "<S-l>", "<cmd>bnext<cr>", { desc = "Next Buffer" })
  map("n", "[b", "<cmd>bprevious<cr>", { desc = "Prev Buffer" })
  map("n", "]b", "<cmd>bnext<cr>", { desc = "Next Buffer" })
  map("n", "<leader>bb", "<cmd>e #<cr>", { desc = "Switch to Other Buffer" })
  map("n", "<leader>`", "<cmd>e #<cr>", { desc = "Switch to Other Buffer" })
  map("n", "<leader>bd", "<cmd>bdelete<cr>", { desc = "Delete Buffer" })
  map("n", "<leader>bo", M.close_others, { desc = "Delete Other Buffers" })

  -- clear search and stop snippet on escape
  map({ "i", "n", "s" }, "<esc>", function()
    vim.cmd("noh")
    return "<esc>"
  end, { expr = true, desc = "Escape and Clear hlsearch" })

  -- redraw / clear hlsearch
  map("n", "<leader>ur", "<Cmd>nohlsearch<Bar>diffupdate<Bar>normal! <C-L><CR>", { desc = "Redraw / Clear hlsearch" })

  -- better n and N
  map("n", "n", "'Nn'[v:searchforward].'zv'", { expr = true, desc = "Next Search Result" })
  map("x", "n", "'Nn'[v:searchforward]", { expr = true, desc = "Next Search Result" })
  map("o", "n", "'Nn'[v:searchforward]", { expr = true, desc = "Next Search Result" })
  map("n", "N", "'nN'[v:searchforward].'zv'", { expr = true, desc = "Prev Search Result" })
  map("x", "N", "'nN'[v:searchforward]", { expr = true, desc = "Prev Search Result" })
  map("o", "N", "'nN'[v:searchforward]", { expr = true, desc = "Prev Search Result" })

  -- undo breakpoints
  map("i", ",", ",<c-g>u")
  map("i", ".", ".<c-g>u")
  map("i", ";", ";<c-g>u")

  -- save
  map({ "i", "x", "n", "s" }, "<C-s>", "<cmd>w<cr><esc>", { desc = "Save File" })

  -- select all
  map("n", "<C-a>", "ggVG", { desc = "Select All (Normal)" })
  map("i", "<C-a>", "<Esc>ggVG", { desc = "Select All (Insert)" })
  map("v", "<C-a>", "<Esc>ggVG", { desc = "Select All (Visual)" })

  map("n", "<leader>K", "<cmd>norm! K<cr>", { desc = "Keywordprg" })

  -- better indenting
  map("x", "<", "<gv")
  map("x", ">", ">gv")

  map("n", "<leader>fn", "<cmd>enew<cr>", { desc = "New File" })

  -- quickfix
  map("n", "<leader>xq", function()
    local success, err = pcall(function()
      if vim.fn.getqflist({ winid = 0 }).winid ~= 0 then
        vim.cmd.cclose()
      else
        vim.cmd.copen()
      end
    end)
    if not success and err then
      vim.notify(err, vim.log.levels.ERROR)
    end
  end, { desc = "Quickfix List" })
  map("n", "[q", vim.cmd.cprev, { desc = "Previous Quickfix" })
  map("n", "]q", vim.cmd.cnext, { desc = "Next Quickfix" })

  -- diagnostics
  map("n", "<leader>cd", vim.diagnostic.open_float, { desc = "Line Diagnostics" })
  map("n", "]d", diagnostic_goto(true), { desc = "Next Diagnostic" })
  map("n", "[d", diagnostic_goto(false), { desc = "Prev Diagnostic" })
  map("n", "]e", diagnostic_goto(true, "ERROR"), { desc = "Next Error" })
  map("n", "[e", diagnostic_goto(false, "ERROR"), { desc = "Prev Error" })
  map("n", "]w", diagnostic_goto(true, "WARN"), { desc = "Next Warning" })
  map("n", "[w", diagnostic_goto(false, "WARN"), { desc = "Prev Warning" })

  -- formatting
  map({ "n", "x" }, "<leader>cf", format, { desc = "Format" })

  -- comment toggle
  map({ "n", "v", "i" }, "<F2>", M.toggle_comment_and_next, { desc = "Toggle comment and move down" })

  -- quick fix / close others
  map("n", "<F11>", M.code_action, { desc = "Quick fix" })
  map("n", "<F12>", M.close_others, { desc = "Close other file buffers" })

  -- build
  map("n", "<leader>cb", function()
    require("config.ComplexKeymaps.build").run()
  end, { desc = "Build (make)" })
  map("n", "<leader>cc", function()
    require("config.ComplexKeymaps.build").run("clean")
  end, { desc = "Clean (make clean)" })

  map("n", "<leader>fw", function()
    vim.notify(vim.fn.expand("%:p"))
  end, { desc = "Show file path" })
end

return M
