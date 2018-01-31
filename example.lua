local cjson = require "cjson"

local ip_block_time=300 --封禁IP时间（秒）
local ip_time_out=1    --指定ip访问频率时间段（秒）
local ip_max_count=500   --指定ip访问频率计数最大值（秒）
local BUSINESS = ngx.var.business --nginx的location中定义的业务标识符
 
--连接redis
local config = {
    name = "testCluster",                   --rediscluster name
    serv_list = {                           --redis cluster node list(host and port),
        { ip = "127.0.0.1", port = 7001 },
        { ip = "127.0.0.1", port = 7002 },
        { ip = "127.0.0.1", port = 7003 },
        { ip = "127.0.0.1", port = 7004 },
        { ip = "127.0.0.1", port = 7005 },
        { ip = "127.0.0.1", port = 7000 }
    },
    enableSlaveRead = true,
    keepalive_timeout = 60000,              --redis connection pool idle timeout
    keepalive_cons = 1000,                  --redis connection pool size
    connection_timout = 1000,               --timeout while connecting
    max_redirection = 5                     --maximum retry attempts for redirection
}
local redis_cluster = require "rediscluster"  
local conn = redis_cluster:new(config) 
 
--查询ip是否被禁止访问，如果存在则返回403错误代码
is_block, err = conn:get(BUSINESS.."-BLOCK-"..ngx.var.remote_addr)  

if err then 
    goto FLAG
end

if is_block == '1' then
    ngx.exit(403)
    goto FLAG
end
 
--查询redis中保存的ip的计数器
ip_count, err = conn:get(BUSINESS.."-COUNT-"..ngx.var.remote_addr)
 
if ip_count == ngx.null then --如果不存在，则将该IP存入redis，并将计数器设置为1、该KEY的超时时间为ip_time_out
    res, err = conn:set(BUSINESS.."-COUNT-"..ngx.var.remote_addr, 1)
    res, err = conn:expire(BUSINESS.."-COUNT-"..ngx.var.remote_addr, ip_time_out)
else
    ip_count = ip_count + 1 --存在则将单位时间内的访问次数加1
  
    if ip_count >= ip_max_count then --如果超过单位时间限制的访问次数，则添加限制访问标识，限制时间为ip_block_time
        res, err = conn:set(BUSINESS.."-BLOCK-"..ngx.var.remote_addr, 1)
        res, err = conn:expire(BUSINESS.."-BLOCK-"..ngx.var.remote_addr, ip_block_time)
    else
        res, err = conn:set(BUSINESS.."-COUNT-"..ngx.var.remote_addr,ip_count)
        res, err = conn:expire(BUSINESS.."-COUNT-"..ngx.var.remote_addr, ip_time_out)
    end
end
 
-- 结束标记
::FLAG::
local ok, err = conn:close()
