local logger = require "resty.logger.socket"
local redis_cluster = require "resty.redis_cluster"
local redis_config = require "request.redis_config"
local json = require "cjson"

local high_prior = ngx.shared.high_prior
local low_prior = ngx.shared.low_prior

local uri = ngx.var.document_uri
if ngx.ctx.low_prior then
   low_prior:incr(uri, 1)
end
if ngx.ctx.high_prior then
   high_prior:incr(uri, 1)
end

local function return_to_redis(premature)
   local rc = redis_cluster:new(redis_config.cluster_id,
                                redis_config.nodes,
                                redis_config.opts)
   rc:initialize()
   local res, err = rc:hget(redis_config.remain_key, uri)
   if not err and tonumber(res) then
      rc:hincrby(redis_config.remain_key, uri, 1)
   end
end
if ngx.ctx.redis then
   ngx.timer.at(0, return_to_redis)
end

local function get_file(file_name) local f = assert(io.open(file_name, "r"))
    local string = f:read("*all")
    f:close()
    return string
end

if not logger.initted() then
   local ok, err = logger.init({
     host = ngx.var.logger_host,
     port = ngx.var.logger_port,
     drop_limit = 9999999,
     pool_size = 20
   })
   if not ok then
      ngx.log(ngx.ERR, "failed to initialize the logger: ",
              err)
      return
   end
end

--ngx.req.read_body()
local body_data = ngx.req.get_body_data()
--ngx.log(ngx.ERR, "body data is: ", body_data)
if not body_data then
   local file_name = ngx.req.get_body_file()
   if file_name then
      body_data = get_file(file_name)
--      ngx.log(ngx.ERR, "read from file, body data is: ", body_data)
   end
end

if body_data then
   body_data = ngx.encode_base64(body_data, true)
   --   ngx.log(ngx.ERR, "encode body data is: ", body_data)
end

local response_time = tonumber(ngx.var.upstream_response_time)
if not response then
   response_time = 0
end

local msg = {
   remote_addr = ngx.var.remote_addr,
   remote_user = ngx.var.remote_user,
   time = ngx.var.time_iso8601,
   uri = ngx.var.document_uri,
   query_string = ngx.var.query_string,
   request_body = body_data,
   status = ngx.var.status,
   referer = ngx.var.http_referer,
   user_agent = ngx.var.http_user_agent,
   x_forwarded_for = ngx.var.http_x_forwarded_for,
   cookie = ngx.var.http_cookie,
   response_time = response_time,
   server_addr = ngx.var.nginx_server_addr
}
           
msg = json.encode(msg) .. string.char(10)

local bytes, err = logger.log(msg)
if err then
    ngx.log(ngx.ERR, "failed to log message: ", err)
    ngx.log(ngx.INFO, "message detail: ",  msg)
    return
end
