local core = require "core"
local config = require "core.config"
local style = require "core.style"
local StatusView = require "core.statusview"


local git = {
  branch = nil,
  inserts = 0,
  deletes = 0,
  file_status = {},
}


local function exec(cmd, wait)
  local tempfile = core.temp_filename()
  system.exec(string.format("%s > %q", cmd, tempfile))
  coroutine.yield(wait)
  local fp = io.open(tempfile)
  local res = fp:read("*a")
  fp:close()
  os.remove(tempfile)
  return res
end


core.add_thread(function()
  while true do
    if system.get_file_info(".git") then
      -- get branch name
      git.branch = exec("git rev-parse --abbrev-ref HEAD", 1):match("[^\n]*")

      -- get diff
      local line = exec("git diff --stat", 1):match("[^\n]*%s*$")
      git.inserts = tonumber(line:match("(%d+) ins")) or 0
      git.deletes = tonumber(line:match("(%d+) del")) or 0

      -- per-file status
      local porcelain = exec("git status --porcelain", 1)
      git.file_status = {}
      for line in porcelain:gmatch("[^\r\n]+") do
        local staged = line:sub(1, 1)
        local unstaged = line:sub(2, 2)
        local path = line:sub(4)
        -- ignore empty paths and rename/copy detection lines
        if path ~= "" and not path:find(" -> ") then
          local abs = system.absolute_path(path)
          if abs then
            git.file_status[abs] = { staged = staged, unstaged = unstaged }
          end
        end
      end

    else
      git.branch = nil
      git.file_status = {}
    end

    coroutine.yield(config.project_scan_rate)
  end
end)

core.git = git


local get_items = StatusView.get_items

function StatusView:get_items()
  if not git.branch then
    return get_items(self)
  end
  local left, right = get_items(self)

  local t = {
    style.dim, self.separator,
    (git.inserts ~= 0 or git.deletes ~= 0) and style.accent or style.text,
    git.branch,
    style.dim, "  ",
    git.inserts ~= 0 and style.accent or style.text, "+", git.inserts,
    style.dim, " / ",
    git.deletes ~= 0 and style.accent or style.text, "-", git.deletes,
  }
  for _, item in ipairs(t) do
    table.insert(right, item)
  end

  return left, right
end

