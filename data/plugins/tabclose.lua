-- TabClose plugin for lite text editor
-- Adds an "X" close button to the right of each file tab

local core = require "core"
local common = require "core.common"
local style = require "core.style"


local close_button_width = 16 * SCALE
local close_button_padding = 4 * SCALE


-- Compute tab rect (mirrors Node:get_tab_rect)
local function get_tab_rect(node, idx)
  local tw = math.min(style.tab_width, math.ceil(node.size.x / #node.views))
  local h = style.font:get_height() + style.padding.y * 2
  return node.position.x + (idx - 1) * tw, node.position.y, tw, h
end


-- Compute close button rect for a tab
local function get_close_button_rect(node, idx)
  local x, y, w, h = get_tab_rect(node, idx)
  local bx = x + w - close_button_width - close_button_padding
  local by = y + (h - style.icon_font:get_height()) / 2
  return bx, by, close_button_width, h
end


-- Check if point is over a close button of a leaf node
local function hit_close_button(node, px, py)
  if #node.views <= 1 then return nil end
  for i = 1, #node.views do
    local bx, by, bw, bh = get_close_button_rect(node, i)
    if px >= bx and py >= by and px < bx + bw and py < by + bh then
      return i
    end
  end
  return nil
end


-- Get all leaf nodes in the tree
local function get_leaf_nodes(node, result)
  result = result or {}
  if node.type == "leaf" then
    table.insert(result, node)
  else
    get_leaf_nodes(node.a, result)
    get_leaf_nodes(node.b, result)
  end
  return result
end


-- Draw close buttons over all tabs in a leaf node
local function draw_close_buttons(node)
  if #node.views <= 1 then return end

  local x, y, _, h = get_tab_rect(node, 1)
  local ds = style.divider_size
  core.push_clip_rect(x, y, node.size.x, h)

  for i, view in ipairs(node.views) do
    local bx, by, bw, bh = get_close_button_rect(node, i)
    local is_hovered_close = (node.hovered_close_tab == i)

    if is_hovered_close then
      renderer.draw_rect(bx, by, bw, bh, style.selection)
    end

    local btn_color = is_hovered_close and style.text or style.dim
    local icon_w = style.icon_font:get_width("x")
    renderer.draw_text(style.icon_font, "x",
      bx + (bw - icon_w) / 2, by, btn_color)
  end

  core.pop_clip_rect()
end


-- Patch RootView:on_mouse_moved to track close button hover
local original_mouse_moved = core.root_view.on_mouse_moved
function core.root_view:on_mouse_moved(x, y, dx, dy)
  if self.dragged_divider then
    local node = self.dragged_divider
    local locked_a = node.a and node.a.locked
    local locked_b = node.b and node.b.locked
    if locked_a ~= locked_b then
      local locked = locked_a and node.a or node.b
      local axis = node.type == "hsplit" and "x" or "y"
      local delta = node.type == "hsplit" and dx or dy
      local sign = locked_a and 1 or -1
      local min_size = 1
      local max_size = math.max(min_size, node.size[axis] - style.divider_size - min_size)
      local new_size = common.clamp(locked.active_view.size[axis] + delta * sign, min_size, max_size)
      locked.active_view.size[axis] = new_size
      if locked.active_view.on_drag_resize then
        locked.active_view:on_drag_resize(axis, new_size)
      end
    else
      if node.type == "hsplit" then
        node.divider = node.divider + dx / node.size.x
      else
        node.divider = node.divider + dy / node.size.y
      end
      node.divider = common.clamp(node.divider, 0.01, 0.99)
    end
    return
  end

  self.mouse.x, self.mouse.y = x, y

  -- Track close button hover on all leaf nodes
  local leaves = get_leaf_nodes(self.root_node)
  for _, node in ipairs(leaves) do
    node.hovered_close_tab = hit_close_button(node, x, y)
  end

  -- Forward to original
  original_mouse_moved(self, x, y, dx, dy)

  -- Override cursor if hovering over a close button
  local node = self.root_node:get_child_overlapping_point(x, y)
  if hit_close_button(node, x, y) then
    system.set_cursor("arrow")
  end
end


-- Patch RootView:on_mouse_pressed to handle close button clicks
local original_mouse_pressed = core.root_view.on_mouse_pressed
function core.root_view:on_mouse_pressed(button, x, y, clicks)
  local node = self.root_node:get_child_overlapping_point(x, y)

  -- Check for close button click first
  local close_tab_idx = hit_close_button(node, x, y)
  if close_tab_idx then
    local view_to_close = node.views[close_tab_idx]
    if node.active_view ~= view_to_close then
      node:set_active_view(view_to_close)
    end
    node:close_active_view(core.root_view)
    return
  end

  -- Fall through to original
  original_mouse_pressed(self, button, x, y, clicks)
end


-- Patch RootView:draw to draw close buttons on top of tabs
local original_draw = core.root_view.draw
function core.root_view:draw()
  original_draw(self)

  -- Draw close buttons on top
  local leaves = get_leaf_nodes(self.root_node)
  for _, node in ipairs(leaves) do
    draw_close_buttons(node)
  end
end


return {}
