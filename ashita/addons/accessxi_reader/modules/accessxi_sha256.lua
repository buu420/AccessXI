local module = {}

local UINT32 = 4294967296
local UINT32_MAX = UINT32 - 1
local bit_backend = bit

local round_constants = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

local initial_state = {
    0x6a09e667,
    0xbb67ae85,
    0x3c6ef372,
    0xa54ff53a,
    0x510e527f,
    0x9b05688c,
    0x1f83d9ab,
    0x5be0cd19,
}

local identity_fields = {
    'size_low',
    'size_high',
    'write_time_low',
    'write_time_high',
}

local function u32(value)
    return value % UINT32
end

local function bit_backend_error()
    if type(bit_backend) ~= 'table' then
        return 'LuaJIT bit library is unavailable'
    end
    for _, name in ipairs({ 'band', 'bxor', 'bnot', 'rshift', 'ror' }) do
        if type(bit_backend[name]) ~= 'function' then
            return ('LuaJIT bit.%s is unavailable'):format(name)
        end
    end
    return nil
end

local function band(a, b)
    return u32(bit_backend.band(a, b))
end

local function bxor(a, b)
    return u32(bit_backend.bxor(a, b))
end

local function bxor3(a, b, c)
    return bxor(bxor(a, b), c)
end

local function bnot(value)
    return u32(bit_backend.bnot(value))
end

local function rshift(value, shift)
    return u32(bit_backend.rshift(value, shift))
end

local function ror(value, shift)
    return u32(bit_backend.ror(value, shift))
end

local function add2(a, b)
    return u32(a + b)
end

local function add4(a, b, c, d)
    return u32(a + b + c + d)
end

local function add5(a, b, c, d, e)
    return u32(a + b + c + d + e)
end

local function add_byte_count(context, count)
    local total = context.length_low + count
    context.length_low = total % UINT32
    context.length_high = (context.length_high + math.floor(total / UINT32)) % UINT32
end

local function compress(context, bytes, offset)
    local schedule = {}
    for index = 1, 16 do
        local position = offset + ((index - 1) * 4)
        local a, b, c, d = bytes:byte(position, position + 3)
        schedule[index] = (a * 16777216) + (b * 65536) + (c * 256) + d
    end

    for index = 17, 64 do
        local left = schedule[index - 15]
        local right = schedule[index - 2]
        local sigma_zero = bxor3(ror(left, 7), ror(left, 18), rshift(left, 3))
        local sigma_one = bxor3(ror(right, 17), ror(right, 19), rshift(right, 10))
        schedule[index] = add4(schedule[index - 16], sigma_zero, schedule[index - 7], sigma_one)
    end

    local a = context.state[1]
    local b = context.state[2]
    local c = context.state[3]
    local d = context.state[4]
    local e = context.state[5]
    local f = context.state[6]
    local g = context.state[7]
    local h = context.state[8]

    for index = 1, 64 do
        local sum_one = bxor3(ror(e, 6), ror(e, 11), ror(e, 25))
        local choose = bxor(band(e, f), band(bnot(e), g))
        local temporary_one = add5(h, sum_one, choose, round_constants[index], schedule[index])
        local sum_zero = bxor3(ror(a, 2), ror(a, 13), ror(a, 22))
        local majority = bxor3(band(a, b), band(a, c), band(b, c))
        local temporary_two = add2(sum_zero, majority)

        h = g
        g = f
        f = e
        e = add2(d, temporary_one)
        d = c
        c = b
        b = a
        a = add2(temporary_one, temporary_two)
    end

    context.state[1] = add2(context.state[1], a)
    context.state[2] = add2(context.state[2], b)
    context.state[3] = add2(context.state[3], c)
    context.state[4] = add2(context.state[4], d)
    context.state[5] = add2(context.state[5], e)
    context.state[6] = add2(context.state[6], f)
    context.state[7] = add2(context.state[7], g)
    context.state[8] = add2(context.state[8], h)
end

local function new_context()
    local state = {}
    for index = 1, 8 do
        state[index] = initial_state[index]
    end
    return {
        state = state,
        buffer = '',
        length_low = 0,
        length_high = 0,
    }
end

local function update_context(context, bytes)
    if #bytes == 0 then
        return
    end
    add_byte_count(context, #bytes)
    local combined = context.buffer .. bytes
    local complete_length = #combined - (#combined % 64)
    for offset = 1, complete_length, 64 do
        compress(context, combined, offset)
    end
    context.buffer = combined:sub(complete_length + 1)
end

local function word_bytes(value)
    value = u32(value)
    return string.char(
        math.floor(value / 16777216) % 256,
        math.floor(value / 65536) % 256,
        math.floor(value / 256) % 256,
        value % 256
    )
end

local hex_digits = '0123456789abcdef'

local function word_hex(value)
    value = u32(value)
    local result = {}
    for shift = 28, 0, -4 do
        local digit = math.floor(value / (2 ^ shift)) % 16
        result[#result + 1] = hex_digits:sub(digit + 1, digit + 1)
    end
    return table.concat(result)
end

local function finish_context(context)
    local bit_length_low = (context.length_low * 8) % UINT32
    local bit_length_high = (
        (context.length_high * 8) + math.floor(context.length_low / 536870912)
    ) % UINT32
    local zero_count = (56 - ((#context.buffer + 1) % 64)) % 64
    local final_bytes = context.buffer
        .. string.char(128)
        .. string.rep(string.char(0), zero_count)
        .. word_bytes(bit_length_high)
        .. word_bytes(bit_length_low)
    for offset = 1, #final_bytes, 64 do
        compress(context, final_bytes, offset)
    end

    local result = {}
    for index = 1, 8 do
        result[index] = word_hex(context.state[index])
    end
    return table.concat(result)
end

function module.sha256(bytes)
    local backend_error = bit_backend_error()
    if backend_error then
        return nil, backend_error
    end
    if type(bytes) ~= 'string' then
        return nil, 'SHA-256 input must be a string of exact bytes'
    end
    local context = new_context()
    update_context(context, bytes)
    return finish_context(context)
end

function module.smoke_test()
    local backend_error = bit_backend_error()
    if backend_error then
        return nil, backend_error
    end
    local ok, digest, reason = pcall(module.sha256, 'abc')
    if not ok then
        return nil, 'LuaJIT bit SHA-256 smoke test raised an error: ' .. tostring(digest)
    end
    if not digest then
        return nil, reason or 'LuaJIT bit SHA-256 smoke test failed'
    end
    if digest ~= 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad' then
        return nil, 'LuaJIT bit SHA-256 abc smoke vector did not match'
    end
    return true
end

local function copy_identity(identity)
    return {
        size_low = identity.size_low,
        size_high = identity.size_high,
        write_time_low = identity.write_time_low,
        write_time_high = identity.write_time_high,
    }
end

local function checked_identity(candidate)
    if type(candidate) ~= 'table' then
        return nil, 'file stat did not return the exact four-word identity'
    end
    local result = {}
    for _, field in ipairs(identity_fields) do
        local value = candidate[field]
        if type(value) ~= 'number'
            or value < 0
            or value > UINT32_MAX
            or value ~= math.floor(value)
        then
            return nil, ('file stat %s is not an exact uint32 word'):format(field)
        end
        result[field] = value
    end
    return result
end

local function same_identity(left, right)
    for _, field in ipairs(identity_fields) do
        if left[field] ~= right[field] then
            return false
        end
    end
    return true
end

local function cache_key(path, identity)
    return table.concat({
        tostring(#path),
        ':',
        path,
        '|',
        ('%.0f'):format(identity.size_low),
        '|',
        ('%.0f'):format(identity.size_high),
        '|',
        ('%.0f'):format(identity.write_time_low),
        '|',
        ('%.0f'):format(identity.write_time_high),
    })
end

local function count_exceeds_identity(low, high, identity)
    if high ~= identity.size_high then
        return high > identity.size_high
    end
    return low > identity.size_low
end

local function count_matches_identity(low, high, identity)
    return low == identity.size_low and high == identity.size_high
end

local function add_count(low, high, count)
    local total = low + count
    return total % UINT32, (high + math.floor(total / UINT32)) % UINT32
end

local file_hasher_methods = {}
file_hasher_methods.__index = file_hasher_methods

function file_hasher_methods:_canonical_path(path)
    if type(path) ~= 'string' or path == '' then
        return nil, 'file path must be a non-empty string'
    end
    local ok, canonical, reason = pcall(self._canonicalize, path)
    if not ok then
        return nil, 'canonical path resolution failed: ' .. tostring(canonical)
    end
    if type(canonical) ~= 'string' or canonical == '' then
        return nil, 'canonical path resolution failed: ' .. tostring(reason or canonical)
    end
    return canonical
end

function file_hasher_methods:_stat_identity(path)
    local ok, candidate, reason = pcall(self._stat, path)
    if not ok then
        return nil, 'file stat failed: ' .. tostring(candidate)
    end
    if candidate == nil then
        return nil, 'file stat failed: ' .. tostring(reason or 'missing file')
    end
    local identity, identity_error = checked_identity(candidate)
    if not identity then
        return nil, identity_error
    end
    return identity
end

local function close_file(file)
    local ok_method, close_method = pcall(function() return file.close end)
    if not ok_method or type(close_method) ~= 'function' then
        return nil, 'file close method is unavailable'
    end
    local ok, closed, reason = pcall(close_method, file)
    if not ok then
        return nil, 'file close failed: ' .. tostring(closed)
    end
    if closed == nil or closed == false then
        return nil, 'file close failed: ' .. tostring(reason or 'unknown error')
    end
    return true
end

local function read_method_for(file)
    local ok, read_method = pcall(function() return file.read end)
    if not ok or type(read_method) ~= 'function' then
        return nil, 'file read method is unavailable'
    end
    return read_method
end

local function read_failure(reason)
    return nil, nil, nil, reason
end

function file_hasher_methods:read_and_hash_file(path)
    local canonical, canonical_error = self:_canonical_path(path)
    if not canonical then
        return read_failure(canonical_error)
    end

    local before, stat_error = self:_stat_identity(canonical)
    if not before then
        return read_failure(stat_error)
    end

    local key = cache_key(canonical, before)
    local cached = self._cache[key]
    if cached then
        return cached.bytes, cached.digest, copy_identity(cached.identity)
    end

    local open_ok, file, open_error = pcall(self._open, canonical, 'rb')
    if not open_ok then
        return read_failure('file open failed: ' .. tostring(file))
    end
    if file == nil then
        return read_failure('file open failed: ' .. tostring(open_error or 'unknown error'))
    end

    local read_method, method_error = read_method_for(file)
    if not read_method then
        close_file(file)
        return read_failure(method_error)
    end

    local context = new_context()
    local pieces = {}
    local bytes_low = 0
    local bytes_high = 0
    local stream_error = nil

    while true do
        local read_ok, piece, piece_error = pcall(read_method, file, self._chunk_size)
        if not read_ok then
            stream_error = 'file read failed: ' .. tostring(piece)
            break
        end
        if piece == nil then
            if piece_error ~= nil then
                stream_error = 'file read failed: ' .. tostring(piece_error)
            end
            break
        end
        if type(piece) ~= 'string' then
            stream_error = 'file read failed: reader returned a non-string chunk'
            break
        end
        if #piece == 0 then
            stream_error = 'file read failed: reader returned an empty chunk before EOF'
            break
        end

        pieces[#pieces + 1] = piece
        update_context(context, piece)
        bytes_low, bytes_high = add_count(bytes_low, bytes_high, #piece)
        if count_exceeds_identity(bytes_low, bytes_high, before) then
            stream_error = 'file size exceeded the pre-read stat identity'
            break
        end
    end

    if stream_error then
        close_file(file)
        return read_failure(stream_error)
    end

    local after, after_error = self:_stat_identity(canonical)
    local close_ok, close_error = close_file(file)
    if not after then
        return read_failure(after_error)
    end
    if not close_ok then
        return read_failure(close_error)
    end
    if not same_identity(before, after) then
        return read_failure('file changed during the read/hash transaction')
    end
    if not count_matches_identity(bytes_low, bytes_high, before) then
        return read_failure('file size did not match the pre-read stat identity')
    end

    local bytes = table.concat(pieces)
    local digest = finish_context(context)
    local stored_identity = copy_identity(before)
    self._cache[key] = {
        bytes = bytes,
        digest = digest,
        identity = stored_identity,
    }
    return bytes, digest, copy_identity(stored_identity)
end

function file_hasher_methods:hash_file(path)
    local bytes, digest, identity, reason = self:read_and_hash_file(path)
    if bytes == nil then
        return nil, nil, reason
    end
    return digest, identity
end

function module.new_file_hasher(options)
    if type(options) ~= 'table' then
        return nil, 'file hasher options must be a table'
    end
    if type(options.canonicalize) ~= 'function' then
        return nil, 'file hasher canonicalize option must be a function'
    end
    if type(options.stat) ~= 'function' then
        return nil, 'file hasher stat option must be a function'
    end
    if type(options.open) ~= 'function' then
        return nil, 'file hasher open option must be a function'
    end
    local chunk_size = options.chunk_size or 65536
    if type(chunk_size) ~= 'number'
        or chunk_size < 1
        or chunk_size ~= math.floor(chunk_size)
    then
        return nil, 'file hasher chunk_size must be a positive integer'
    end
    return setmetatable({
        _canonicalize = options.canonicalize,
        _stat = options.stat,
        _open = options.open,
        _chunk_size = chunk_size,
        _cache = {},
    }, file_hasher_methods)
end

return module
