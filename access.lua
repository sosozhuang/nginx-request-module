local redis_cluster = require "resty.redis_cluster"
local redis_config = require "request.redis_config"
local rc
local function reject()
   ngx.exit(ngx.HTTP_FORBIDDEN)
end

local ip = ngx.var.remote_addr
local blocked = ngx.shared.blocked
local b = blocked:get(ip)
if b then
   reject()
   return
end

local limit_config = ngx.shared.limit_config
local high_prior = ngx.shared.high_prior
local low_prior = ngx.shared.low_prior

local level = limit_config:get('level')
local uri = ngx.var.document_uri

local function level_1()
   local remain = low_prior:get(uri)
   if not remain then
      return
   end
   if remain <= 0 then
      local res, err = rc:hget(redis_config.remain_key, uri)
      if err then
         reject()
         return
      end
      remain = tonumber(res)
      if not remain or remain <= 0 then
         reject()
         return
      else
         rc:hincrby(redis_config.remain_key, uri, -1)
         ngx.ctx.redis = true
      end
   else
      low_prior:incr(uri, -1)
      ngx.ctx.low_prior = true
   end
end
local function level_2()
   if low_prior:get(uri) then
      reject()
   end
end
local function level_3()
   ngx.log(ngx.ERR, 'level 3 enter')
   if not high_prior:get(uri) then
      reject()
   end
end
local function level_4()
   local remain = high_prior:get(uri)
   if not remain or remain <= 0 then
      local res, err = rc:hget(redis_config.remain_key, uri)
      if err then
         reject()
         return  
      end     
      remain = tonumber(res)
      if not remain or remain <= 0 then
         reject()
         return  
      else    
         rc:hincrby(redis_config.remain_key, uri, -1)
         ngx.ctx.redis = true
      end
   else
      high_prior:incr(uri, -1)
      ngx.ctx.high_prior = true
   end
end
local function init_redis()
   rc = redis_cluster:new(redis_config.cluster_id, 
                          redis_config.nodes, 
                          redis_config.opts)
   rc:initialize()
end
local functor = {level_1, level_2, level_3, level_4, reject}
if not level or level == 0 then
   return
else
   init_redis()
   functor[level]()
end
