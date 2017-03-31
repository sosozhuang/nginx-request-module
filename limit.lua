local json = require "cjson.safe"
local redis_cluster = require "resty.redis_cluster"
local redis_config = require "request.redis_config"
local _M = {}
local mt = { __index = _M }
local limit_config = ngx.shared.limit_config
local high_prior = ngx.shared.high_prior
local low_prior = ngx.shared.low_prior
local rc

local function get_file(file_name)
    local f = assert(io.open(file_name, "r"))
    local string = f:read("*all")
    f:close()
    return string
end

local function get_body_data()
    ngx.req.read_body()
    local body_data = ngx.req.get_body_data()
    if not body_data then
       local file_name = ngx.req.get_body_file()
       if file_name then
          body_data = get_file(file_name)
       end
    end
    return body_data
end

local function set_level()
    local level = ngx.var.arg_level
    if not level or not tonumber(level) then
       ngx.say('limit level must between 0 and 5')
       return
    end
    level = tonumber(level)
    if level < 0 or level > 5 then
       ngx.say('limit level must between 0 and 5')
       return
    end
    limit_config:set('level', level)
    ngx.log(ngx.ERR, 'setting limit level on: ', level)
    ngx.say('ok')
end

local function set_redis_limit_conf(v)
        local prev_value, err = rc:hget(redis_config.config_key, v.uri)
        if err then
           ngx.say('fail to hget config uri: ', v.uri)
           return
        end
        local _, err = rc:hset(redis_config.config_key, v.uri, v.global)
        if err then
           ngx.say('fail to hset config uri: ', v.uri)
           return
        end
        local remain, err = rc:hget(redis_config.remain_key, v.uri)
        if err then
           ngx.say('fail to hget remain uri: ', v.uri)
           return
        end
        if not tonumber(remain) then
           local _, err = rc:hset(redis_config.remain_key, v.uri, v.global)
           if err then
              ngx.say('fail to hset remain uri: ', v.uri)
              return
           end
        else
           prev_value = tonumber(prev_value)
           if not prev_value then
              prev_value = 0
           end
           local _, err = rc:hincrby(redis_config.remain_key, v.uri, v.global - prev_value)
           if err then
              ngx.say('fail to hincrby remain uri: ', v.uri)
              return
           end
        end 

end

local function set_limit_conf()
    local body_data = get_body_data()
    if not body_data then
       ngx.say('request body is empty')
       return
    end

    local json_data = json.decode(body_data)
    if not json_data then
       ngx.say('decode request body to json failed')
       return
    end
    
    for _, v in ipairs(json_data) do
        if type(v.uri) ~= "string" then
           ngx.say('illegal uri param: ' .. v.uri)
           return
        end
        if type(v.level) ~= "number" then
           ngx.say('illegal level param: ' .. v.level)
           return
        end
        if type(v.nlocal) ~= "number" or v.nlocal < 0 then
           ngx.say('illegal nlocal param: ' .. v.nlocal)
           return
        end
        if v.global 
           and (type(v.global) ~= "number" or v.global < 0) then
           ngx.say('illegal global param: ' .. v.global)
           return
        end
        local prev_value = limit_config:get(v.uri)
        if not prev_value then
           prev_value = 0
        end
        limit_config:set(v.uri, v.nlocal)

        if v.level == 1 then
           local remain = low_prior:get(v.uri)
           if not remain then
              low_prior:set(v.uri, v.nlocal) 
           else
              low_prior:incr(v.uri, v.nlocal - prev_value)
           end
        elseif v.level == 2 then
           local remain = high_prior:get(v.uri)
           if not remain then
              high_prior:set(v.uri, v.nlocal) 
           else
              high_prior:incr(v.uri, v.nlocal - prev_value)
           end
        else
           ngx.log(ngx.ERR, 'illegal level param: ', v.level)
        end

        if v.global > 0 then
           set_redis_limit_conf(v)
        end
    end

    ngx.say('ok')
    
end

local function unset_limit_conf()
    local body_data = get_body_data()
    if not body_data then
       ngx.say('request body is null')
       return  
    end

    local json_data = json.decode(body_data)
    if not json_data then
       ngx.say('decode request body to json failed')
       return  
    end
    
    for _, v in ipairs(json_data) do
        limit_config:delete(v.uri)

        low_prior:delete(v.uri)
        high_prior:delete(v.uri)

        rc:hdel(redis_config.config_key, v.uri)
        rc:hdel(redis_config.remain_key, v.uri)
    end

    ngx.say('ok')

end

local function flush_all()
    limit_config:flush_all()
    high_prior:flush_all()
    low_prior:flush_all()
    rc:del(redis_config.config_key)
    rc:del(redis_config.remain_key)
    ngx.say('ok')
end

local function inspect()
    local level = limit_config:get('level')
    if not level then
       level = 0
    end
    local high_prior_data = {}
    for _, key in ipairs(high_prior:get_keys()) do
        local nlocal = limit_config:get(key)
        local global = rc:hget(redis_config.config_key, key)
        local remain = high_prior:get(key)
        local gremain = rc:hget(redis_config.remain_key, key)
        if nlocal or (tonumber(global) and tonumber(global)) then
           high_prior_data[key] = {
               nlocal = nlocal, 
               remain = remain,
               global = tonumber(global),
               gremain = tonumber(gremain)
           }
        end
    end
    local low_prior_data = {}
    for _, key in ipairs(low_prior:get_keys()) do
        local nlocal = limit_config:get(key)
        local global = rc:hget(redis_config.config_key, key)
        local remain = low_prior:get(key)
        local gremain = rc:hget(redis_config.remain_key, key)
        if nlocal or (tonumber(global) and tonumber(global)) then
           low_prior_data[key] = {
               nlocal = nlocal, 
               remain = remain,
               global = tonumber(global),
               gremain = tonumber(gremain)
           }
        end
    end
    local msg = {
        level = level,
        high_prior = high_prior_data,
        low_prior = low_prior_data
    }
    msg = json.encode(msg)
    ngx.say(msg)
end

local functor = {set_level = set_level,
                 set_limit_conf = set_limit_conf,
                 unset_limit_conf = unset_limit_conf,
                 flush_all = flush_all,
                 inspect = inspect}
function _M.process()
    local action = ngx.var.arg_action
    if not action then
       ngx.say('illegal url query string: action is empty')
       return
    end
    local f = functor[action]
    if not f then
       ngx.say('illegal url query string: ' .. action)
       return
    end
    rc = redis_cluster:new(redis_config.cluster_id, 
                           redis_config.nodes, 
                           redis_config.opts)
    rc:initialize()
    f()
end
return _M
