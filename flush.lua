local logger = require "resty.logger.socket"

if not logger.initted() then
   ngx.say('logger is not initted, does not have to flush')
else
   local _, err = logger.flush()
   if not err then
      ngx.say('logger has been flushed')
   else
      ngx.say('failed to flush logger, reason: ', err)
   end
end
