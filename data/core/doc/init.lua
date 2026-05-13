local Object = require "core.object"
local Highlighter = require "core.doc.highlighter"
local syntax = require "core.syntax"
local config = require "core.config"
local common = require "core.common"


local Doc = Object:extend()


local function split_lines(text)
  local res = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    table.insert(res, line)
  end
  return res
end


local function splice(t, at, remove, insert)
  insert = insert or {}
  local offset = #insert - remove
  local old_len = #t
  if offset < 0 then
    for i = at - offset, old_len - offset do
      t[i + offset] = t[i]
    end
  elseif offset > 0 then
    for i = old_len, at, -1 do
      t[i + offset] = t[i]
    end
  end
  for i, item in ipairs(insert) do
    t[at + i - 1] = item
  end
end


function Doc:new(filename)
  self:reset()
  if filename then
    self:load(filename)
  end
end


function Doc:reset()
  self.lines = { "\n" }
  self.selections = { 1, 1, 1, 1 }
  self.undo_stack = { idx = 1 }
  self.redo_stack = { idx = 1 }
  self.clean_change_id = 1
  self.highlighter = Highlighter(self)
  self:reset_syntax()
end


function Doc:reset_syntax()
  local header = self:get_text(1, 1, self:position_offset(1, 1, 128))
  local syn = syntax.get(self.filename or "", header)
  if self.syntax ~= syn then
    self.syntax = syn
    self.highlighter:reset()
  end
end


function Doc:load(filename)
  local fp = assert( io.open(filename, "rb") )
  self:reset()
  self.filename = filename
  self.lines = {}
  for line in fp:lines() do
    if line:byte(-1) == 13 then
      line = line:sub(1, -2)
      self.crlf = true
    end
    table.insert(self.lines, line .. "\n")
  end
  if #self.lines == 0 then
    table.insert(self.lines, "\n")
  end
  fp:close()
  self:reset_syntax()
end


function Doc:save(filename)
  filename = filename or assert(self.filename, "no filename set to default to")
  local fp = assert( io.open(filename, "wb") )
  for _, line in ipairs(self.lines) do
    if self.crlf then line = line:gsub("\n", "\r\n") end
    fp:write(line)
  end
  fp:close()
  self.filename = filename or self.filename
  self:reset_syntax()
  self:clean()
end


function Doc:get_name()
  return self.filename or "unsaved"
end


function Doc:is_dirty()
  return self.clean_change_id ~= self:get_change_id()
end


function Doc:clean()
  self.clean_change_id = self:get_change_id()
end


function Doc:get_change_id()
  return self.undo_stack.idx
end


function Doc:set_selection(line1, col1, line2, col2, swap)
  if not line2 then
    line1, col1 = self:sanitize_position(line1, col1)
    line2, col2 = line1, col1
  else
    if swap then line1, col1, line2, col2 = line2, col2, line1, col1 end
    line1, col1 = self:sanitize_position(line1, col1)
    line2, col2 = self:sanitize_position(line2, col2)
  end
  self.selections = { line1, col1, line2, col2 }
end


local function sort_positions(line1, col1, line2, col2)
  if line1 > line2
  or line1 == line2 and col1 > col2 then
    return line2, col2, line1, col1, true
  end
  return line1, col1, line2, col2, false
end


function Doc:get_selection(sort)
  local n = #self.selections
  local l1, c1, l2, c2 = self.selections[n-3], self.selections[n-2], self.selections[n-1], self.selections[n]
  if sort then
    return sort_positions(l1, c1, l2, c2)
  end
  return l1, c1, l2, c2
end


function Doc:set_selection_at(idx, line1, col1, line2, col2, swap)
  if swap then line1, col1, line2, col2 = line2, col2, line1, col1 end
  line1, col1 = self:sanitize_position(line1, col1)
  line2, col2 = self:sanitize_position(line2 or line1, col2 or col1)
  local i = (idx - 1) * 4 + 1
  self.selections[i] = line1
  self.selections[i+1] = col1
  self.selections[i+2] = line2
  self.selections[i+3] = col2
end


function Doc:has_selection()
  for i = 1, #self.selections, 4 do
    if self.selections[i] ~= self.selections[i+2] or self.selections[i+1] ~= self.selections[i+3] then
      return true
    end
  end
  return false
end


function Doc:add_selection(line1, col1, line2, col2, swap)
  if swap then line1, col1, line2, col2 = line2, col2, line1, col1 end
  line1, col1 = self:sanitize_position(line1, col1)
  line2, col2 = self:sanitize_position(line2 or line1, col2 or col1)
  table.insert(self.selections, line1)
  table.insert(self.selections, col1)
  table.insert(self.selections, line2)
  table.insert(self.selections, col2)
  self:sanitize_selection()
end


function Doc:remove_selection(idx)
  table.remove(self.selections, (idx - 1) * 4 + 4)
  table.remove(self.selections, (idx - 1) * 4 + 3)
  table.remove(self.selections, (idx - 1) * 4 + 2)
  table.remove(self.selections, (idx - 1) * 4 + 1)
end


function Doc:sanitize_selection()
  -- clamp selections to document bounds
  for i = 1, #self.selections, 4 do
    self.selections[i], self.selections[i+1] = self:sanitize_position(self.selections[i], self.selections[i+1])
    self.selections[i+2], self.selections[i+3] = self:sanitize_position(self.selections[i+2], self.selections[i+3])
  end

  -- sort each individual selection so (l1, c1) is the start and (l2, c2) is the end
  -- and also collect them into a sortable list of objects
  local sorted = {}
  for i = 1, #self.selections, 4 do
    local l1, c1, l2, c2 = self.selections[i], self.selections[i+1], self.selections[i+2], self.selections[i+3]
    local swap = l1 > l2 or (l1 == l2 and c1 > c2)
    if swap then l1, c1, l2, c2 = l2, c2, l1, c1 end
    table.insert(sorted, { l1 = l1, c1 = c1, l2 = l2, c2 = c2, swap = swap })
  end

  -- sort selections by their start position
  table.sort(sorted, function(a, b)
    if a.l1 ~= b.l1 then return a.l1 < b.l1 end
    return a.c1 < b.c1
  end)

  -- merge overlapping or adjacent selections
  local i = 1
  while i < #sorted do
    local a, b = sorted[i], sorted[i+1]
    if b.l1 < a.l2 or (b.l1 == a.l2 and b.c1 <= a.c2) then
      if b.l2 > a.l2 or (b.l2 == a.l2 and b.c2 > a.c2) then
        a.l2, a.c2 = b.l2, b.c2
      end
      table.remove(sorted, i + 1)
    else
      i = i + 1
    end
  end

  -- flatten back into self.selections
  self.selections = {}
  for _, s in ipairs(sorted) do
    if s.swap then
      table.insert(self.selections, s.l2); table.insert(self.selections, s.c2)
      table.insert(self.selections, s.l1); table.insert(self.selections, s.c1)
    else
      table.insert(self.selections, s.l1); table.insert(self.selections, s.c1)
      table.insert(self.selections, s.l2); table.insert(self.selections, s.c2)
    end
  end
end


function Doc:sanitize_position(line, col)
  line = common.clamp(line, 1, #self.lines)
  col = common.clamp(col, 1, #self.lines[line])
  return line, col
end


local function position_offset_func(self, line, col, fn, ...)
  line, col = self:sanitize_position(line, col)
  return fn(self, line, col, ...)
end


local function position_offset_byte(self, line, col, offset)
  line, col = self:sanitize_position(line, col)
  col = col + offset
  while line > 1 and col < 1 do
    line = line - 1
    col = col + #self.lines[line]
  end
  while line < #self.lines and col > #self.lines[line] do
    col = col - #self.lines[line]
    line = line + 1
  end
  return self:sanitize_position(line, col)
end


local function position_offset_linecol(self, line, col, lineoffset, coloffset)
  return self:sanitize_position(line + lineoffset, col + coloffset)
end


function Doc:position_offset(line, col, ...)
  if type(...) ~= "number" then
    return position_offset_func(self, line, col, ...)
  elseif select("#", ...) == 1 then
    return position_offset_byte(self, line, col, ...)
  elseif select("#", ...) == 2 then
    return position_offset_linecol(self, line, col, ...)
  else
    error("bad number of arguments")
  end
end


function Doc:get_text(line1, col1, line2, col2)
  line1, col1 = self:sanitize_position(line1, col1)
  line2, col2 = self:sanitize_position(line2, col2)
  line1, col1, line2, col2 = sort_positions(line1, col1, line2, col2)
  if line1 == line2 then
    return self.lines[line1]:sub(col1, col2 - 1)
  end
  local lines = { self.lines[line1]:sub(col1) }
  for i = line1 + 1, line2 - 1 do
    table.insert(lines, self.lines[i])
  end
  table.insert(lines, self.lines[line2]:sub(1, col2 - 1))
  return table.concat(lines)
end


function Doc:get_char(line, col)
  line, col = self:sanitize_position(line, col)
  return self.lines[line]:sub(col, col)
end


local function push_undo(undo_stack, time, type, ...)
  undo_stack[undo_stack.idx] = { type = type, time = time, ... }
  undo_stack[undo_stack.idx - config.max_undos] = nil
  undo_stack.idx = undo_stack.idx + 1
end


local function pop_undo(self, undo_stack, redo_stack)
  -- pop command
  local cmd = undo_stack[undo_stack.idx - 1]
  if not cmd then return end
  undo_stack.idx = undo_stack.idx - 1

  -- handle command
  if cmd.type == "insert" then
    local line, col, text = table.unpack(cmd)
    self:raw_insert(line, col, text, redo_stack, cmd.time)

  elseif cmd.type == "remove" then
    local line1, col1, line2, col2 = table.unpack(cmd)
    self:raw_remove(line1, col1, line2, col2, redo_stack, cmd.time)

  elseif cmd.type == "selection" then
    self.selections = { table.unpack(cmd) }
  end

  -- if next undo command is within the merge timeout then treat as a single
  -- command and continue to execute it
  local next = undo_stack[undo_stack.idx - 1]
  if next and math.abs(cmd.time - next.time) < config.undo_merge_timeout then
    return pop_undo(self, undo_stack, redo_stack)
  end
end


function Doc:raw_insert(line, col, text, undo_stack, time)
  -- push undo
  local line2, col2 = self:position_offset(line, col, #text)
  push_undo(undo_stack, time, "selection", table.unpack(self.selections))
  push_undo(undo_stack, time, "remove", line, col, line2, col2)

  -- split text into lines and merge with line at insertion point
  local lines = split_lines(text)
  local before = self.lines[line]:sub(1, col - 1)
  local after = self.lines[line]:sub(col)
  for i = 1, #lines - 1 do
    lines[i] = lines[i] .. "\n"
  end
  lines[1] = before .. lines[1]
  lines[#lines] = lines[#lines] .. after

  -- splice lines into line array
  splice(self.lines, line, 1, lines)

  -- shift trailing selections
  local line_diff = line2 - line
  local col_diff = col2 - col
  for i = 1, #self.selections, 2 do
    local l, c = self.selections[i], self.selections[i+1]
    if l > line then
      self.selections[i] = l + line_diff
    elseif l == line and c >= col then
      self.selections[i], self.selections[i+1] = l + line_diff, c + col_diff
    end
  end

  -- update highlighter and assure selection is in bounds
  self.highlighter:invalidate(line)
  self:sanitize_selection()
end


function Doc:raw_remove(line1, col1, line2, col2, undo_stack, time)
  -- push undo
  local text = self:get_text(line1, col1, line2, col2)
  push_undo(undo_stack, time, "selection", table.unpack(self.selections))
  push_undo(undo_stack, time, "insert", line1, col1, text)

  -- get line content before/after removed text
  local before = self.lines[line1]:sub(1, col1 - 1)
  local after = self.lines[line2]:sub(col2)

  -- splice line into line array
  splice(self.lines, line1, line2 - line1 + 1, { before .. after })

  -- shift trailing selections
  local line_diff = line2 - line1
  local col_diff = col2 - col1
  for i = 1, #self.selections, 2 do
    local l, c = self.selections[i], self.selections[i+1]
    if l > line2 then
      self.selections[i] = l - line_diff
    elseif l == line2 and c >= col2 then
      self.selections[i], self.selections[i+1] = l - line_diff, c - col_diff
    elseif l > line1 or (l == line1 and c > col1) then
      self.selections[i], self.selections[i+1] = line1, col1
    end
  end

  -- update highlighter and assure selection is in bounds
  self.highlighter:invalidate(line1)
  self:sanitize_selection()
end


function Doc:insert(line, col, text)
  self.redo_stack = { idx = 1 }
  line, col = self:sanitize_position(line, col)
  self:raw_insert(line, col, text, self.undo_stack, system.get_time())
end


function Doc:remove(line1, col1, line2, col2)
  self.redo_stack = { idx = 1 }
  line1, col1 = self:sanitize_position(line1, col1)
  line2, col2 = self:sanitize_position(line2, col2)
  line1, col1, line2, col2 = sort_positions(line1, col1, line2, col2)
  self:raw_remove(line1, col1, line2, col2, self.undo_stack, system.get_time())
end


function Doc:undo()
  pop_undo(self, self.undo_stack, self.redo_stack)
end


function Doc:redo()
  pop_undo(self, self.redo_stack, self.undo_stack)
end


function Doc:text_input(text)
  if self:has_selection() then
    self:delete_to()
  end
  for i = 1, #self.selections, 4 do
    local line, col = self.selections[i], self.selections[i+1]
    self:insert(line, col, text)
  end
end


function Doc:replace(fn)
  local n_accum = 0
  for i = 1, #self.selections, 4 do
    local l1, c1, l2, c2 = self.selections[i], self.selections[i+1], self.selections[i+2], self.selections[i+3]
    local line1, col1, line2, col2, swap = sort_positions(l1, c1, l2, c2)
    local old_text = self:get_text(line1, col1, line2, col2)
    local new_text, n = fn(old_text)
    if old_text ~= new_text then
      self:insert(line2, col2, new_text)
      self:remove(line1, col1, line2, col2)
    end
    n_accum = n_accum + (n or 0)
  end
  return n_accum
end


function Doc:delete_to(...)
  if self:has_selection() then
    for i = 1, #self.selections, 4 do
      local l1, c1, l2, c2 = self.selections[i], self.selections[i+1], self.selections[i+2], self.selections[i+3]
      if l1 ~= l2 or c1 ~= c2 then
        self:remove(l1, c1, l2, c2)
      end
    end
  else
    for i = 1, #self.selections, 4 do
      local l1, c1 = self.selections[i], self.selections[i+1]
      local l2, c2 = self.position_offset(self, l1, c1, ...)
      self:remove(l1, c1, l2, c2)
    end
  end
end


function Doc:move_to(...)
  for i = 1, #self.selections, 4 do
    local line, col = self.selections[i], self.selections[i+1]
    line, col = self:position_offset(line, col, ...)
    self.selections[i], self.selections[i+1], self.selections[i+2], self.selections[i+3] = line, col, line, col
  end
  self:sanitize_selection()
end


function Doc:select_to(...)
  for i = 1, #self.selections, 4 do
    local line, col = self.selections[i], self.selections[i+1]
    line, col = self:position_offset(line, col, ...)
    self.selections[i], self.selections[i+1] = line, col
  end
  self:sanitize_selection()
end


return Doc
