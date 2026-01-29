local core = require "core"
local style = require "core.style"
local Doc = require "core.doc"
local DocView = require "core.docview"


local function split_lines(text)
  local res = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    table.insert(res, line .. "\n")
  end
  if #res == 0 then
    res[1] = "\n"
  end
  return res
end


local function append_lines(lines, prefix, text)
  local first = true
  local pad = string.rep(" ", #prefix)
  for line in (text .. "\n"):gmatch("(.-)\n") do
    if line ~= "" or first then
      table.insert(lines, (first and prefix or pad) .. line)
      first = false
    end
  end
end


local function build_log_text()
  local lines = {}
  for i = #core.log_items, 1, -1 do
    local item = core.log_items[i]
    local time = os.date(nil, item.time)
    local prefix = time .. " "
    append_lines(lines, prefix, item.text)
    if item.info then
      table.insert(lines, string.rep(" ", #prefix) .. "at " .. item.at)
      append_lines(lines, string.rep(" ", #prefix), item.info)
    end
  end
  return table.concat(lines, "\n")
end


local LogDoc = Doc:extend()

function LogDoc:get_name()
  return "Log"
end

function LogDoc:insert()
end

function LogDoc:remove()
end

function LogDoc:text_input()
end

function LogDoc:replace()
end

function LogDoc:delete_to()
end

function LogDoc:undo()
end

function LogDoc:redo()
end

function LogDoc:set_text(text)
  local selection = { self:get_selection() }
  self:reset()
  self.lines = split_lines(text)
  self.highlighter:invalidate(1)
  self:clean()
  self:set_selection(table.unpack(selection))
end


local LogView = DocView:extend()

function LogView:new()
  LogView.super.new(self, LogDoc())
  self.font = "font"
  self.last_item = nil
end


function LogView:get_name()
  return "Log"
end


function LogView:get_gutter_width()
  return style.padding.x
end


function LogView:draw_line_gutter()
end


function LogView:update()
  local item = core.log_items[#core.log_items]
  if self.last_item ~= item then
    self.last_item = item
    self.doc:set_text(build_log_text())
    self.scroll.to.y = 0
  end

  LogView.super.update(self)
end


return LogView
