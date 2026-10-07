-- Cinematic Noir — Neovim colorscheme (keep in sync with ~/.config/theme/colors.sh)
local p = {
  base = "#0D0D13",
  surface = "#161720",
  surface_alt = "#1D2030",
  border = "#30344B",
  fg = "#D0D2DF",
  muted = "#6D7291",
  blue = "#6672B8",
  blue_bright = "#6F78C4",
  purple = "#8B68B5",
  amber = "#B07855",
  red = "#A76565",
  green = "#668B78",
  yellow = "#B09A69",
  cyan = "#608D9A",
  magenta = "#80639A",
}

vim.g.colors_name = "cinematic_noir"
vim.o.termguicolors = true
vim.o.background = "dark"

local function hi(group, opts)
  vim.api.nvim_set_hl(0, group, opts)
end

-- UI
hi("Normal", { fg = p.fg, bg = p.base })
hi("NormalFloat", { fg = p.fg, bg = p.surface })
hi("FloatBorder", { fg = p.border, bg = p.surface })
hi("NormalNC", { fg = p.fg, bg = p.base })
hi("Cursor", { fg = p.base, bg = p.blue_bright })
hi("CursorLine", { bg = p.surface })
hi("CursorColumn", { bg = p.surface })
hi("CursorLineNr", { fg = p.fg, bold = true })
hi("LineNr", { fg = p.muted })
hi("SignColumn", { fg = p.muted, bg = p.base })
hi("ColorColumn", { bg = p.surface })
hi("Visual", { bg = p.border })
hi("VisualNOS", { bg = p.surface_alt })
hi("Search", { fg = p.base, bg = p.amber })
hi("IncSearch", { fg = p.base, bg = p.blue_bright })
hi("MatchParen", { fg = p.blue_bright, bold = true, underline = true })
hi("Whitespace", { fg = p.border })
hi("NonText", { fg = p.border })
hi("SpecialKey", { fg = p.border })
hi("VertSplit", { fg = p.border, bg = p.base })
hi("WinSeparator", { fg = p.border, bg = p.base })
hi("StatusLine", { fg = p.fg, bg = p.surface })
hi("StatusLineNC", { fg = p.muted, bg = p.surface })
hi("TabLine", { fg = p.muted, bg = p.surface })
hi("TabLineFill", { bg = p.surface })
hi("TabLineSel", { fg = p.fg, bg = p.surface_alt, bold = true })
hi("Pmenu", { fg = p.fg, bg = p.surface })
hi("PmenuSel", { fg = p.fg, bg = p.border })
hi("PmenuSbar", { bg = p.surface_alt })
hi("PmenuThumb", { bg = p.muted })
hi("WildMenu", { fg = p.base, bg = p.blue })
hi("Folded", { fg = p.muted, bg = p.surface })
hi("FoldColumn", { fg = p.muted, bg = p.base })
hi("Title", { fg = p.blue_bright, bold = true })
hi("Directory", { fg = p.blue })
hi("Question", { fg = p.green })
hi("MoreMsg", { fg = p.green })
hi("ModeMsg", { fg = p.fg, bold = true })
hi("ErrorMsg", { fg = p.red, bold = true })
hi("WarningMsg", { fg = p.amber })
hi("Todo", { fg = p.amber, bold = true })

-- Syntax
hi("Comment", { fg = p.muted, italic = true })
hi("Constant", { fg = p.yellow })
hi("String", { fg = p.green })
hi("Character", { fg = p.green })
hi("Number", { fg = p.yellow })
hi("Boolean", { fg = p.amber })
hi("Float", { fg = p.yellow })
hi("Identifier", { fg = p.fg })
hi("Function", { fg = p.blue_bright })
hi("Statement", { fg = p.purple })
hi("Conditional", { fg = p.purple })
hi("Repeat", { fg = p.purple })
hi("Label", { fg = p.purple })
hi("Operator", { fg = p.cyan })
hi("Keyword", { fg = p.purple })
hi("Exception", { fg = p.red })
hi("PreProc", { fg = p.cyan })
hi("Include", { fg = p.cyan })
hi("Define", { fg = p.cyan })
hi("Macro", { fg = p.cyan })
hi("Type", { fg = p.blue })
hi("StorageClass", { fg = p.purple })
hi("Structure", { fg = p.blue })
hi("Typedef", { fg = p.blue })
hi("Special", { fg = p.amber })
hi("SpecialChar", { fg = p.amber })
hi("Tag", { fg = p.blue })
hi("Delimiter", { fg = p.muted })
hi("SpecialComment", { fg = p.muted, italic = true })
hi("Underlined", { underline = true })
hi("Ignore", { fg = p.muted })
hi("Error", { fg = p.red })

-- Diff
hi("DiffAdd", { fg = p.green, bg = p.surface })
hi("DiffChange", { fg = p.yellow, bg = p.surface })
hi("DiffDelete", { fg = p.red, bg = p.surface })
hi("DiffText", { fg = p.blue_bright, bg = p.surface_alt, bold = true })

-- Diagnostics
hi("DiagnosticError", { fg = p.red })
hi("DiagnosticWarn", { fg = p.amber })
hi("DiagnosticInfo", { fg = p.blue })
hi("DiagnosticHint", { fg = p.cyan })
hi("DiagnosticUnderlineError", { undercurl = true, sp = p.red })
hi("DiagnosticUnderlineWarn", { undercurl = true, sp = p.amber })
hi("DiagnosticUnderlineInfo", { undercurl = true, sp = p.blue })
hi("DiagnosticUnderlineHint", { undercurl = true, sp = p.cyan })

-- Treesitter (links)
hi("@comment", { link = "Comment" })
hi("@string", { link = "String" })
hi("@number", { link = "Number" })
hi("@boolean", { link = "Boolean" })
hi("@function", { link = "Function" })
hi("@function.call", { link = "Function" })
hi("@method", { link = "Function" })
hi("@keyword", { link = "Keyword" })
hi("@type", { link = "Type" })
hi("@variable", { link = "Identifier" })
hi("@variable.parameter", { fg = p.amber })
hi("@property", { fg = p.fg })
hi("@operator", { link = "Operator" })
hi("@punctuation", { link = "Delimiter" })
hi("@tag", { link = "Tag" })
hi("@attribute", { fg = p.purple })
hi("@constant", { link = "Constant" })
hi("@constructor", { fg = p.blue })
