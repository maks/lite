local core = require "core"
local command = require "core.command"
local keymap = require "core.keymap"
local DocView = require "core.docview"

local history = {}
local history_idx = 0
local is_navigating = false

local function push_history(filename, line, col)
  if is_navigating or not filename then return end

  -- Truncate forward history if we moved away from the history path
  if history_idx < #history then
    while #history > history_idx do
      table.remove(history)
    end
  end

  -- Don't push if it's the same as the last one
  local last = history[#history]
  if last and last.filename == filename and math.abs(last.line - line) < 5 then
    return
  end

  table.insert(history, { filename = filename, line = line, col = col })
  history_idx = #history

  if #history > 100 then
    table.remove(history, 1)
    history_idx = history_idx - 1
  end
end


-- Patch core.set_active_view to record positions when switching buffers
local set_active_view = core.set_active_view
core.set_active_view = function(view)
  if view ~= core.active_view and core.active_view and core.active_view:is(DocView) then
    local av = core.active_view
    if av.doc.filename then
      push_history(av.doc.filename, av.doc:get_selection())
    end
  end
  set_active_view(view)
end


-- Patch DocView:update to record significant jumps within a file
local update = DocView.update
function DocView:update(...)
  if core.active_view == self and self.last_line and self.doc.filename then
    local line, col = self.doc:get_selection()
    if math.abs(self.last_line - line) > 20 then
      push_history(self.doc.filename, self.last_line, self.last_col)
    end
  end
  return update(self, ...)
end


command.add("core.docview", {
  ["history:back"] = function()
    local av = core.active_view
    if not av or not av.doc.filename then return end

    -- If we are at the latest position and it's not recorded, push it
    if history_idx == #history then
      local line, col = av.doc:get_selection()
      push_history(av.doc.filename, line, col)
    end

    if history_idx > 1 then
      history_idx = history_idx - 1
      local item = history[history_idx]
      is_navigating = true
      core.root_view:open_doc(core.open_doc(item.filename))
      core.active_view.doc:set_selection(item.line, item.col)
      core.active_view:scroll_to_line(item.line, true)
      is_navigating = false
    end
  end,

  ["history:forward"] = function()
    if history_idx < #history then
      history_idx = history_idx + 1
      local item = history[history_idx]
      is_navigating = true
      core.root_view:open_doc(core.open_doc(item.filename))
      core.active_view.doc:set_selection(item.line, item.col)
      core.active_view:scroll_to_line(item.line, true)
      is_navigating = false
    end
  end,

  ["history:clear"] = function()
    history = {}
    history_idx = 0
  end,
})

keymap.add {
  ["alt+left"] = "history:back",
  ["alt+right"] = "history:forward",
}
