local _M = {}
_M.cluster_id = "my_redis"
_M.nodes = {
    {"192.168.1.100", 6379},
    {"192.168.1.101", 5379}
}
_M.opts = {
    timeout = 100,
    keepalive_size = 20,
    keepalive_duration = 60000 
}
_M.config_key = "ngx_limit_config"
_M.remain_key = "ngx_limit_remain"

return _M
