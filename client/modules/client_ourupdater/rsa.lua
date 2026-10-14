-- OurTibia (02.10.2026): RSA-SHA256 (PKCS#1 v1.5) signature check in plain Lua
-- for the client update manifest. Only the public key operation is needed
-- (e = 65537), done with Montgomery multiplication on 22-bit limbs so every
-- intermediate value stays an exact double.
OurRSA = {}

local W = 4194304 -- 2^22
local floor = math.floor

local function bytesToLimbs(bytes, count)
  local limbs, acc, bits = {}, 0, 0
  for i = #bytes, 1, -1 do
    acc = acc + bytes:byte(i) * 2 ^ bits
    bits = bits + 8
    while bits >= 22 do
      limbs[#limbs + 1] = acc % W
      acc = floor(acc / W)
      bits = bits - 22
    end
  end
  if bits > 0 then limbs[#limbs + 1] = acc end
  for i = #limbs + 1, count or #limbs do limbs[i] = 0 end
  return limbs
end

local function limbsToBytes(limbs, length)
  local out, acc, bits, li = {}, 0, 0, 1
  for i = length, 1, -1 do
    while bits < 8 do
      acc = acc + (limbs[li] or 0) * 2 ^ bits
      li = li + 1
      bits = bits + 22
    end
    out[i] = string.char(acc % 256)
    acc = floor(acc / 256)
    bits = bits - 8
  end
  return table.concat(out)
end

local function geq(a, n, s)
  for i = s, 1, -1 do
    if a[i] ~= n[i] then return a[i] > n[i] end
  end
  return true
end

local function sub(a, n, s)
  local borrow = 0
  for i = 1, s do
    local v = a[i] - n[i] - borrow
    if v < 0 then v = v + W; borrow = 1 else borrow = 0 end
    a[i] = v
  end
end

local function montmul(a, b, n, np, s)
  local t = {}
  for i = 1, s + 2 do t[i] = 0 end
  for i = 1, s do
    local bi, c = b[i], 0
    for j = 1, s do
      local v = t[j] + a[j] * bi + c
      c = floor(v / W); t[j] = v - c * W
    end
    local v = t[s + 1] + c
    c = floor(v / W); t[s + 1] = v - c * W; t[s + 2] = c
    local m = (t[1] * np) % W
    v = t[1] + m * n[1]
    c = floor(v / W)
    for j = 2, s do
      v = t[j] + m * n[j] + c
      c = floor(v / W); t[j - 1] = v - c * W
    end
    v = t[s + 1] + c
    c = floor(v / W); t[s] = v - c * W
    t[s + 1] = t[s + 2] + c
  end
  local r = {}
  for i = 1, s do r[i] = t[i] end
  if t[s + 1] > 0 or geq(r, n, s) then sub(r, n, s) end
  return r
end

-- Returns signature^65537 mod modulus as a big-endian byte string.
function OurRSA.publicOp(signature, modulus)
  local k = #modulus
  local s = math.ceil(k * 8 / 22)
  local n = bytesToLimbs(modulus, s)
  local x = bytesToLimbs(signature, s)
  if geq(x, n, s) then return nil end
  -- n' = -n^-1 mod 2^22 (Newton iteration, n is odd)
  local n0 = n[1]
  local inv = n0
  for _ = 1, 5 do
    local t = (n0 * inv) % W
    inv = (inv * ((2 - t) % W)) % W
  end
  local np = (W - inv) % W
  -- x * R mod n by doubling (R = 2^(22*s))
  local xm = {}
  for i = 1, s do xm[i] = x[i] end
  for _ = 1, 22 * s do
    local c = 0
    for i = 1, s do
      local v = xm[i] * 2 + c
      if v >= W then xm[i] = v - W; c = 1 else xm[i] = v; c = 0 end
    end
    if c == 1 or geq(xm, n, s) then sub(xm, n, s) end
  end
  local acc = xm
  for _ = 1, 16 do acc = montmul(acc, acc, n, np, s) end
  acc = montmul(acc, xm, n, np, s)
  local one = {1}
  for i = 2, s do one[i] = 0 end
  acc = montmul(acc, one, n, np, s)
  return limbsToBytes(acc, k)
end

local SHA256_PREFIX = '\48\49\48\13\6\9\96\134\72\1\101\3\4\2\1\5\0\4\32'

-- signature, modulus: raw big-endian byte strings; digestHex: sha256 hex.
function OurRSA.verifySha256(signature, modulus, digestHex)
  if type(signature) ~= 'string' or type(modulus) ~= 'string' or #signature ~= #modulus then return false end
  if type(digestHex) ~= 'string' or #digestHex ~= 64 then return false end
  local digest = digestHex:gsub('..', function(h) return string.char(tonumber(h, 16)) end)
  local k = #modulus
  local tail = SHA256_PREFIX .. digest
  local expected = '\0\1' .. string.rep('\255', k - 3 - #tail) .. '\0' .. tail
  local ok, em = pcall(OurRSA.publicOp, signature, modulus)
  return ok and em == expected
end
