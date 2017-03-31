local _M = {}
local mt = { __index = _M }
local function block(it)
    local blocked = ngx.shared.blocked
    for _, v in ipairs(it) do
           ngx.log(ngx.ERR, "block ip in blocked: ", v)
           blocked:set(v, 1)
    end
end

local function free(it)
    local blocked = ngx.shared.blocked
    for _, v in ipairs(it) do
           ngx.log(ngx.ERR, "delete ip in blocked: ", v)
           blocked:delete(v)
    end
end

local functor = {block = block, free = free}

function _M.process()
    local blocked = ngx.shared.blocked
    local ips = ngx.var.arg_ips
    local action = ngx.var.arg_action
    if not ips or not action then
       ngx.log(ngx.ERR, "request ips or action is nil")
       return
    end
    
    for it,err in ngx.re.gmatch(ips, "([^',']+)") do
        if not it then
           ngx.log(ngx.ERR, "gmatch {} ips error: ", action, err)
           return
        end
        functor[action](it)
    end

    ngx.say("ok")
end

function _M.free_ip()
    local blocked = ngx.shared.blocked
    local ips = ngx.var.arg_ips
    if not ips then
      ngx.log(ngx.ERR, "request free ips is nil")
      return
   end
   for it,err in ngx.re.gmatch(ips, "([^',']+)") do
       if not it then
          ngx.log(ngx.ERR, "gmatch block ips error: ", err)
          return
       end
       for _, v in ipairs(it) do
           blocked:delete(v)
       end
   end

    ngx.say("ok")
end

function _M.block_ip()
   local blocked = ngx.shared.blocked
   local ips = ngx.var.arg_ips
   if not ips then
      ngx.log(ngx.ERR, "request block ips is nil")
      return
   end
   for it,err in ngx.re.gmatch(ips, "([^',']+)") do
       if not it then
          ngx.log(ngx.ERR, "gmatch block ips error: ", err)
          return
       end
       for _, v in ipairs(it) do
           blocked:set(v, "1")
           ngx.log(ngx.ERR, "add block ip: ", v) 
       end
   end
   ngx.say("ok")
end

return _M
