local sha2 = require("sha2")
local crypto = {}

crypto.sha256 = sha2.hash256
crypto.sha224 = sha2.hash224
crypto.sha256obj = sha2.new256

return crypto