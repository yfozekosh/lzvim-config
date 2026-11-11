return {
  "sindrets/diffview.nvim",
  -- Loading this at startup costs ~58ms for a plugin that is only used when
  -- explicitly opened; let its commands pull it in.
  cmd = {
    "DiffviewOpen",
    "DiffviewClose",
    "DiffviewToggleFiles",
    "DiffviewFocusFiles",
    "DiffviewRefresh",
    "DiffviewFileHistory",
  },
}
