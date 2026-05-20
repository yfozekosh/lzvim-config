local function open_racket_help()
  -- Create a new buffer for the help content
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, "filetype", "help")
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")

  -- Help content
  local help_content = {
    "╔════════════════════════════════════════════════════════════════════════╗",
    "║                      RACKET NEOVIM GUIDE                              ║",
    "╚════════════════════════════════════════════════════════════════════════╝",
    "",
    "═══════════════════════════════════════════════════════════════════════════",
    "1. STRUCTURAL EDITING WITH PARINFER",
    "═══════════════════════════════════════════════════════════════════════════",
    "",
    "Parinfer automatically maintains correct indentation and parentheses as",
    "you type. Just write code naturally and Parinfer fixes the structure.",
    "",
    "HOW IT WORKS (SMART MODE):",
    "  Parinfer watches your cursor position and indentation as you edit.",
    "  It works on every keystroke in INSERT mode to maintain proper syntax.",
    "  You won't see explicit commands - it's automatic!",
    "",
    "WHAT TO TEST:",
    "  1. Enter insert mode (i or o)",
    "  2. Type: (if true",
    "  3. Press Enter to go to next line",
    "  4. Type:   'yes",
    "  5. Press Enter again",
    "  6. Type:   'no",
    "     → Parinfer should automatically add closing ) after 'no",
    "",
    "KEY BEHAVIORS:",
    "  • Type opening paren '(' - Parinfer balances it automatically",
    "  • Indent/dedent - Parinfer adds/removes closing parens as needed",
    "  • Delete closing paren - Parinfer adds it back to match indentation",
    "  • Multi-line forms - Parinfer infers structure from your indentation",
    "",
    "EXAMPLE WORKFLOW:",
    "  Step 1: Type (define (square x",
    "  Step 2: Press Enter",
    "  Step 3: Type   (* x x",
    "  → Result: Parinfer automatically closes with closing parens",
    "",
     "═══════════════════════════════════════════════════════════════════════════",
     "2. EXPLICIT STRUCTURAL EDITING WITH VIM-SEXP",
     "═══════════════════════════════════════════════════════════════════════════",
     "",
     "Vim-sexp provides commands for moving, wrapping, and manipulating s-expressions.",
     "Use these when you need explicit control beyond Parinfer's automatic fixing.",
     "",
     "NAVIGATION & MOVEMENT:",
     "  (                Jump to previous opening paren/bracket",
     "  )                Jump to next opening paren/bracket",
     "  [[               Jump to previous top-level s-expression",
     "  ]]               Jump to next top-level s-expression",
     "  [e               Select and move to previous element",
     "  ]e               Select and move to next element",
     "  <M-b>            Jump to head of previous symbol/element",
     "  <M-w>            Jump to head of next symbol/element",
     "",
     "WRAPPING FORMS:",
     "  <LocalLeader>i   Wrap current list in ( ) - insert at head",
     "  <LocalLeader>I   Wrap current list in ( ) - insert at tail",
     "  <LocalLeader>[   Wrap current list in [ ] - insert at head",
     "  <LocalLeader>]   Wrap current list in [ ] - insert at tail",
     "  <LocalLeader>{   Wrap current list in { } - insert at head",
     "  <LocalLeader>}   Wrap current list in { } - insert at tail",
     "  <LocalLeader>w   Wrap element at cursor in ( ) - head position",
     "  <LocalLeader>W   Wrap element at cursor in ( ) - tail position",
     "",
     "SPLICING & RAISING:",
     "  <LocalLeader>@   Remove parens/brackets around current form",
     "  <LocalLeader>o   Replace parent list with current list",
     "  <LocalLeader>O   Replace parent list with current element",
     "",
      "SWAPPING & REORDERING:",
      "  <M-k>            Swap current compound form (list) backward",
      "  <M-j>            Swap current compound form (list) forward",
      "  <M-h>            Swap current element backward",
      "  <M-l>            Swap current element forward",
     "",
     "TEXT OBJECT SELECTION:",
     "  af               Select form with all brackets and contents",
     "  if               Select form contents only (no brackets)",
     "  as               Select string with quotes",
     "  is               Select string contents only (no quotes)",
     "  ae               Select one element/symbol",
     "  ie               Select element without surrounding space",
     "",
      "EXAMPLES:",
      "  Starting with: (+ 1 (* 2 3))",
      "  Cursor on (* 2 3), <M-j> → (* 2 3) (+ 1)  [swap form forward]",
      "  Cursor inside (* 2 3), <M-l> → (* 3 2)  [swap element forward]",
    "",
    "═══════════════════════════════════════════════════════════════════════════",
    "3. PARENTHESIS HIGHLIGHTING",
    "═══════════════════════════════════════════════════════════════════════════",
    "",
    "Two types of parenthesis highlighting:",
    "",
    "RAINBOW DELIMITERS (Automatic):",
    "  • Different nesting levels get different colors",
    "  • Makes it easy to track bracket matching visually",
    "  • Works automatically, no keybindings needed",
    "",
    "MATCHPAREN (Under Cursor):",
    "  • When cursor is on '(' or ')', its matching pair highlights",
    "  • Helps navigate nested structures",
    "  • Works automatically when cursor is positioned on any bracket",
    "",
    "═══════════════════════════════════════════════════════════════════════════",
    "4. CONJURE - REPL INTEGRATION",
    "═══════════════════════════════════════════════════════════════════════════",
    "",
    "Conjure lets you evaluate Racket code directly from your editor without",
    "leaving Neovim. Results appear inline or in a REPL buffer.",
    "",
    "KEY KEYBINDINGS:",
    "  <leader>r      Run entire file in terminal (custom)",
    "  <localleader>e Evaluate top-level form under cursor",
    "  <localleader>E Evaluate entire buffer",
    "  <localleader>l Load file into REPL session",
    "  <localleader>q Quit REPL session",
    "  <localleader>1 Open REPL in window 1",
    "  <localleader>2 Open REPL in window 2",
    "",
    "EXAMPLES:",
    "  1. Place cursor on: (+ 1 2)",
    "     Press: <localleader>e",
    "     Result: Evaluates (+ 1 2) and shows '3' inline",
    "",
    "  2. Place cursor on: (define x 42)",
    "     Press: <localleader>e",
    "     Result: Defines x in REPL, can use in next evaluations",
    "",
    "  3. Full file execution:",
    "     Press: <leader>r",
    "     Result: Runs entire file in terminal below editor",
    "",
    "═══════════════════════════════════════════════════════════════════════════",
    "5. LANGUAGE SERVER PROTOCOL (LSP)",
    "═══════════════════════════════════════════════════════════════════════════",
    "",
    "Provides code intelligence: hover docs, goto definition, references, etc.",
    "",
    "KEY KEYBINDINGS:",
    "  K                 Show hover documentation",
    "  gd                Go to definition",
    "  gr                Find references",
    "  gi                Go to implementation",
    "  <leader>ca        Code actions / quick fixes",
    "  <leader>cr        Rename symbol",
    "  <leader>cd        Rename symbol",
    "",
    "EXAMPLES:",
    "  1. Hover over a function: Press K to see its documentation",
    "  2. Jump to definition: Place cursor on function, press gd",
    "  3. Find usages: Press gr to see all references",
    "",
    "═══════════════════════════════════════════════════════════════════════════",
    "6. NAVIGATION",
    "═══════════════════════════════════════════════════════════════════════════",
    "",
    "Standard Vim motions work, plus s-expression aware editing:",
    "",
    "GENERAL MOTIONS:",
    "  %                 Jump between matching parens/brackets",
    "  (                 Move to previous s-expression start",
    "  )                 Move to next s-expression start",
    "  ^                 Move to first non-blank character",
    "  $                 Move to end of line",
    "",
    "═══════════════════════════════════════════════════════════════════════════",
    "7. QUICK REFERENCE - ALL CUSTOM KEYBINDINGS",
    "═══════════════════════════════════════════════════════════════════════════",
    "",
     "EDITING & EXECUTION:",
     "  <leader>r        Execute Racket file in terminal",
     "  <leader>?        Toggle this help window",
     "",
       "STRUCTURAL EDITING (vim-sexp):",
       "  (/)              Jump to prev/next bracket",
       "  [[/]]            Jump to prev/next top-level form",
       "  <LocalLeader>i   Wrap in parentheses",
       "  <LocalLeader>@   Splice (remove brackets)",
       "  <LocalLeader>o   Raise list to replace parent",
       "  <M-j/k>          Swap form forward/backward",
       "  <M-l/h>          Swap element forward/backward",
       "  af/if            Select form with/without brackets",
     "",
      "REPL (via Conjure):",
      "  <localleader>e   Evaluate current expression",
      "  <localleader>E   Evaluate entire file",
      "  <localleader>l   Load file into REPL session",
      "  <localleader>q   Close REPL session",
     "",
      "LSP:",
      "  K                 Show documentation for symbol",
      "  gd                Jump to definition",
      "  gr                Find all references",
     "",
    "═══════════════════════════════════════════════════════════════════════════",
    "8. WORKFLOW EXAMPLE",
    "═══════════════════════════════════════════════════════════════════════════",
    "",
    "Typical Racket development session:",
    "",
    "  1. Open Racket file: vim myfile.rkt",
    "",
    "  2. Write a function with Parinfer auto-balancing:",
    "     (define (factorial n)",
    "       (if (= n 0)",
    "         1",
    "         (* n (factorial (- n 1)))))",
    "",
    "  3. Test with Conjure: Place cursor on function, <localleader>e",
    "     → Evaluates the define, function loaded in REPL",
    "",
    "  4. Test the function: Type (factorial 5) on new line, <localleader>e",
    "     → Shows result: 120",
    "",
    "  5. Jump to definition: Place cursor on 'factorial', press gd",
    "     → Jumps to where factorial is defined",
    "",
    "  6. Run full file: <leader>r",
    "     → Executes entire file in terminal",
    "",
    "═══════════════════════════════════════════════════════════════════════════",
    "9. TIPS & TRICKS",
    "═══════════════════════════════════════════════════════════════════════════",
    "",
    "• PARINFER SMART MODE: Type code naturally, indentation determines structure",
    "• RAINBOW COLORS: Helps understand nesting depth at a glance",
    "• CURSOR ON PAREN: Position cursor on any bracket to see its match highlight",
    "• CONJURE RESULTS: Check the command line or a floating window for results",
    "• HOV ER FOR DOCS: Press K anywhere to see what the LSP knows",
    "",
    "═══════════════════════════════════════════════════════════════════════════",
    "",
    "Press 'q' to close this help buffer",
    "",
  }

  -- Set the content
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, help_content)

  -- Make it read-only
  vim.api.nvim_buf_set_option(buf, "modifiable", false)

  -- Create window with floating position
  local width = 80
  local height = #help_content
  local win_width = vim.api.nvim_get_option("columns")
  local win_height = vim.api.nvim_get_option("lines")

  local col = math.floor((win_width - width) / 2)
  local row = math.floor((win_height - height) / 2)

  local win_opts = {
    relative = "editor",
    width = width,
    height = height,
    col = col,
    row = row,
    style = "minimal",
    border = "rounded",
  }

  local win = vim.api.nvim_open_win(buf, true, win_opts)

  -- Set up keymaps for closing
  vim.api.nvim_buf_set_keymap(buf, "n", "q", ":bd!<CR>", { noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(buf, "n", "<Esc>", ":bd!<CR>", { noremap = true, silent = true })

  -- Make window scrollable if content is too long
  vim.api.nvim_win_set_option(win, "wrap", true)
end

-- Track help buffer state
local help_visible = false

-- Toggle function that tracks state
local function toggle_racket_help()
  -- Check if a help buffer already exists
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == "help" then
      local buf_name = vim.api.nvim_buf_get_name(buf)
      if buf_name == "" then -- It's a temp buffer (our help buffer)
        -- Close it
        vim.api.nvim_buf_delete(buf, { force = true })
        help_visible = false
        return
      end
    end
  end

  -- If not open, open it
  open_racket_help()
  help_visible = true
end

-- Export for use in autocmds
return toggle_racket_help
