local module_path = assert(arg[1], 'missing SHA-256 module path')

local UINT32 = 4294967296
local UINT32_MAX = UINT32 - 1

local function u32(value)
    return (tonumber(value) or 0) % UINT32
end

local function bit2(a, b, truth)
    a = u32(a)
    b = u32(b)
    local result = 0
    local place = 1
    for _ = 0, 31 do
        local aa = a % 2
        local bb = b % 2
        if truth(aa, bb) then
            result = result + place
        end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        place = place * 2
    end
    return result
end

local bit = {}

function bit.band(first, ...)
    local result = u32(first)
    for index = 1, select('#', ...) do
        local value = select(index, ...)
        result = bit2(result, value, function(a, b) return a == 1 and b == 1 end)
    end
    return result
end

function bit.bor(first, ...)
    local result = u32(first)
    for index = 1, select('#', ...) do
        local value = select(index, ...)
        result = bit2(result, value, function(a, b) return a == 1 or b == 1 end)
    end
    return result
end

function bit.bxor(first, ...)
    local result = u32(first)
    for index = 1, select('#', ...) do
        local value = select(index, ...)
        result = bit2(result, value, function(a, b) return a ~= b end)
    end
    return result
end

function bit.bnot(value)
    return UINT32_MAX - u32(value)
end

function bit.rshift(value, shift)
    shift = (tonumber(shift) or 0) % 32
    return math.floor(u32(value) / (2 ^ shift))
end

function bit.lshift(value, shift)
    shift = (tonumber(shift) or 0) % 32
    return u32(u32(value) * (2 ^ shift))
end

function bit.ror(value, shift)
    shift = (tonumber(shift) or 0) % 32
    value = u32(value)
    if shift == 0 then
        return value
    end
    return u32(math.floor(value / (2 ^ shift)) + ((value % (2 ^ shift)) * (2 ^ (32 - shift))))
end

local chunk = assert(loadfile(module_path))
local environment = setmetatable({ bit = bit }, { __index = _G })
setfenv(chunk, environment)
local sha = assert(chunk())

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error(('%s\nexpected: %s\nactual:   %s'):format(message, tostring(expected), tostring(actual)), 2)
    end
end

local function assert_contains(value, fragment, message)
    value = tostring(value or ''):lower()
    fragment = tostring(fragment):lower()
    if not value:find(fragment, 1, true) then
        error(('%s\nexpected fragment: %s\nactual: %s'):format(message, fragment, value), 2)
    end
end

local function assert_digest(message, bytes, expected)
    local actual, reason = sha.sha256(bytes)
    assert_equal(reason, nil, message .. ' must not return an error')
    assert_equal(actual, expected, message)
end

assert_equal(type(sha.sha256), 'function', 'module must expose sha256')
assert_equal(type(sha.new_file_hasher), 'function', 'module must expose new_file_hasher')
assert_equal(type(sha.smoke_test), 'function', 'module must expose the live LuaJIT bit smoke API')

local smoke_ok, smoke_reason = sha.smoke_test()
assert_equal(smoke_ok, true, 'bit/abc smoke test must pass under the deterministic bit shim: ' .. tostring(smoke_reason))
assert_equal(smoke_reason, nil, 'successful smoke test must not return a reason')

assert_digest('NIST empty vector', '', 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855')
assert_digest('NIST abc vector', 'abc', 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad')
assert_digest(
    'NIST long-message vector',
    'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq',
    '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1'
)

assert_digest('NIST million-a vector', string.rep('a', 1000000), 'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0')

local binary_parts = {}
for value = 0, 255 do
    binary_parts[#binary_parts + 1] = string.char(value)
end
assert_digest('binary 00..ff vector', table.concat(binary_parts), '40aff2e9d2d8922e47afd4648e6967497158785fbd1da870e7110266bf944880')

local remainder_digests = {
    'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    '6e340b9cffb37a989ca544e6bb780a2c78901d3fb33738768511a30617afa01d',
    'b413f47d13ee2fe6c845b2ee141af81de858df4ec549a58b7970bb96645bc8d2',
    'ae4b3280e56e2faf83f414a6e3dabe9d5fbe18976544c05fed121accb85b53fc',
    '054edec1d0211f624fed0cbca9d4f9400b0e491c43742af2c5b0abebf0c990d8',
    '08bb5e5d6eaac1049ede0893d30ed022b1a4d9b5b48db414871f51c9cb35283d',
    '17e88db187afd62c16e5debf3e6527cd006bc012bc90b51a810cd80c2d511f43',
    '57355ac3303c148f11aef7cb179456b9232cde33a818dfda2c2fcb9325749a6b',
    '8a851ff82ee7048ad09ec3847f1ddf44944104d2cbd17ef4e3db22c6785a0d45',
    'f8348e0b1df00833cbbbd08f07abdecc10c0efb78829d7828c62a7f36d0cc549',
    '1f825aa2f0020ef7cf91dfa30da4668d791c5d4824fc8e41354b89ec05795ab3',
    '78a6273103d17c39a0b6126e226cec70e33337f4bc6a38067401b54a33e78ead',
    'fff3a9bcdd37363d703c1c4f9512533686157868f0d4f16a0f02d0f1da24f9a2',
    '86eba947d50c2c01570fe1bb5ca552958dabbdbb59b0657f0f26e21ff011e5c7',
    'ab107f1bd632d3c3f5c724a99d024f7faa033f33c07696384b604bfe78ac352d',
    '7071fc3188fde7e7e500d4768f1784bede1a22e991648dcab9dc3219acff1d4c',
    'be45cb2605bf36bebde684841a28f0fd43c69850a3dce5fedba69928ee3a8991',
    '3e5718fea51a8f3f5baca61c77afab473c1810f8b9db330273b4011ce92c787e',
    '7a096cc12702bcfa647ee070d4f3ba4c2d1d715b484b55b825d0edba6545803b',
    '5f9a753613d87b8a17302373c4aee56faa310d3b24b6ae1862d673aa22e1790f',
    'e7aebf577f60412f0312d442c70a1fa6148c090bf5bab404caec29482ae779e8',
    '75aee9dcc9fbe7ddc9394f5bc5d38d9f5ad361f0520f7ceab59616e38f5950b5',
    '22cb4df00cddd6067ad5cfa2bba9857f21a06843e1a6e39ad1a68cb9a45ab8b7',
    'f6a954a68555187d88cd9a026940d15ab2a7e24c7517d21ceeb028e93c96f318',
    '1d64add2a6388367c9bc2d1f1b384b069a6ef382cdaaa89771dd103e28613a25',
    'b729ce724d9a48d3884dbfcbee1d3793d922b29fa9d639e7290af4978263772b',
    'b858da80d8a57dc546905fd147612ebddd3c9188620405d058f9ee5ab1e6bc52',
    'd78750726155a89c9131d0ecf2704b973b8710865bf9e831845de4f2dcbc19da',
    'dc27f8e8ee2d08a2bccbb2dbd6c8e07ffba194101fc3458c34ded55f72c0971a',
    'd09bea65dff48928a14b79741de3274b646f55ac898b71a66fa3eae2d9facd77',
    'f2192584b67da35dfc26f743e5f53bb0376046f899dc6dabd5e7b541ae86c32f',
    '4f23c2ca8c5c962e50cd31e221bfb6d0adca19111dca8e0c62598ff146dd19c4',
    '630dcd2966c4336691125448bbb25b4ff412a49c732db2c8abc1b8581bd710dd',
    '5d8fcfefa9aeeb711fb8ed1e4b7d5c8a9bafa46e8e76e68aa18adce5a10df6ab',
    '14cdbf171499f86bd18b262243d669067efbdbb5431a48289cf02f2b5448b3d4',
    'f12dd12340cb84e4d0d9958d62be7c59bb8f7243a7420fd043177ac542a26aaa',
    '5d7e2d9b1dcbc85e7c890036a2cf2f9fe7b66554f2df08cec6aa9c0a25c99c21',
    'f4d285f47a1e4959a445ea6528e5df3efab041fa15aad94db1e2600b3f395518',
    'a2fd0e15d72c9d18f383e40016f9ddc706673c54252084285aaa47a812552577',
    '4aba23aea5e2a91b7807cf3026cdd10a1c38533ce55332683d4ccb88456e0703',
    '5faa4eec3611556812c2d74b437c8c49add3f910f10063d801441f7d75cd5e3b',
    '753629a6117f5a25d338dff10f4dd3d07e63eecc2eaf8eabe773f6399706fe67',
    '40a1ed73b46030c8d7e88682078c5ab1ae5a2e524e066e8c8743c484de0e21e5',
    'c033843682818c475e187d260d5e2edf0469862dfa3bb0c116f6816a29edbf60',
    '17619ec4250ef65f083e2314ef30af796b6f1198d0fddfbb0f272930bf9bb991',
    'a8e960c769a9508d098451e3d74dd5a2ac6c861eb0341ae94e9fc273597278c9',
    '8ebfeb2e3a159e9f39ad7cc040e6678dade70d4f59a67d529fa76af301ab2946',
    'ef8a7781a95c32fa02ebf511eda3dc6e273be59cb0f9e20a4f84d54f41427791',
    '4dbdc2b2b62cb00749785bc84202236dbc3777d74660611b8e58812f0cfde6c3',
    '7509fe148e2c426ed16c990f22fe8116905c82c561756e723f63223ace0e147e',
    'a622e13829e488422ee72a5fc92cb11d25c3d0f185a1384b8138df5074c983bf',
    '3309847cee454b4f99dcfe8fdc5511a7ba168ce0b6e5684ef73f9030d009b8b5',
    'c4c6540a15fc140a784056fe6d9e13566fb614ecb2d9ac0331e264c386442acd',
    '90962cc12ae9cdae32d7c33c4b93194b11fac835942ee41b98770c6141c66795',
    '675f28acc0b90a72d1c3a570fe83ac565555db358cf01826dc8eefb2bf7ca0f3',
    '463eb28e72f82e0a96c0a4cc53690c571281131f672aa229e0d45ae59b598b59',
    'da2ae4d6b36748f2a318f23e7ab1dfdf45acdc9d049bd80e59de82a60895f562',
    '2fe741af801cc238602ac0ec6a7b0c3a8a87c7fc7d7f02a3fe03d1c12eac4d8f',
    'e03b18640c635b338a92b82cce4ff072f9f1aba9ac5261ee1340f592f35c0499',
    'bd2de8f5dd15c73f68dfd26a614080c2e323b2b51b1b5ed9d7933e535d223bda',
    '0ddde28e40838ef6f9853e887f597d6adb5f40eb35d5763c52e1e64d8ba3bfff',
    '4b5c2783c91ceccb7c839213bcbb6a902d7fe8c2ec866877a51f433ea17f3e85',
    'c89da82cbcd76ddf220e4e9091019b9866ffda72bee30de1effe6c99701a2221',
    '29af2686fd53374a36b0846694cc342177e428d1647515f078784d69cdb9e488',
}

for length = 0, 63 do
    local parts = {}
    for value = 0, length - 1 do
        parts[#parts + 1] = string.char(value)
    end
    assert_digest(('block-remainder vector %d'):format(length), table.concat(parts), remainder_digests[length + 1])
end

local invalid_digest, invalid_reason = sha.sha256({})
assert_equal(invalid_digest, nil, 'non-string direct input must be rejected')
assert_contains(invalid_reason, 'string', 'non-string direct input must explain the required type')

local identity_fields = { 'size_low', 'size_high', 'write_time_low', 'write_time_high' }

local function copy_identity(identity)
    local result = {}
    for _, field in ipairs(identity_fields) do
        result[field] = identity[field]
    end
    return result
end

local function make_identity(size, seed)
    return {
        size_low = size,
        size_high = 0,
        write_time_low = seed or 100,
        write_time_high = 200,
    }
end

local function make_fixture(file_rows, aliases, overrides)
    overrides = overrides or {}
    local state = {
        files = file_rows,
        aliases = aliases or {},
        canonicalize_calls = 0,
        stat_calls = 0,
        open_calls = 0,
        read_calls = 0,
        close_calls = 0,
    }

    local function canonicalize(path)
        state.canonicalize_calls = state.canonicalize_calls + 1
        if overrides.canonicalize then
            return overrides.canonicalize(state, path)
        end
        return state.aliases[path] or path
    end

    local function stat(path)
        state.stat_calls = state.stat_calls + 1
        if overrides.stat then
            return overrides.stat(state, path)
        end
        local row = state.files[path]
        if not row then
            return nil, 'synthetic missing file'
        end
        return copy_identity(row.identity)
    end

    local function open(path, mode)
        state.open_calls = state.open_calls + 1
        if overrides.open then
            return overrides.open(state, path, mode)
        end
        assert_equal(mode, 'rb', 'file hasher must open exact bytes in binary mode')
        local row = state.files[path]
        if not row then
            return nil, 'synthetic open missing file'
        end
        local bytes = row.bytes
        local offset = 1
        local file = {}
        function file:read(count)
            state.read_calls = state.read_calls + 1
            if offset > #bytes then
                return nil
            end
            local value = bytes:sub(offset, offset + count - 1)
            offset = offset + #value
            return value
        end
        function file:close()
            state.close_calls = state.close_calls + 1
            return true
        end
        return file
    end

    local hasher = assert(sha.new_file_hasher({
        canonicalize = canonicalize,
        stat = stat,
        open = open,
        chunk_size = overrides.chunk_size or 7,
    }))
    return state, hasher
end

local canonical_one = 'C:\\fixture\\one.bin'
local canonical_two = 'C:\\fixture\\two.bin'
local shared_identity = make_identity(5, 1000)
local cache_state, cache_hasher = make_fixture({
    [canonical_one] = { bytes = 'alpha', identity = copy_identity(shared_identity) },
    [canonical_two] = { bytes = 'bravo', identity = copy_identity(shared_identity) },
}, {
    ['one-alias'] = canonical_one,
    ['one-other-alias'] = canonical_one,
    ['two-alias'] = canonical_two,
})

local accepted_bytes, accepted_digest, accepted_identity, accepted_reason = cache_hasher:read_and_hash_file('one-alias')
assert_equal(accepted_reason, nil, 'initial read-and-hash must succeed')
assert_equal(accepted_bytes, 'alpha', 'read-and-hash must return the exact accepted bytes')
assert_equal(accepted_digest, sha.sha256(accepted_bytes), 'returned digest must describe the returned bytes')
assert_equal(accepted_identity.size_low, 5, 'read-and-hash must return exact stat identity')
assert_equal(cache_state.open_calls, 1, 'initial read-and-hash must open once')
assert_equal(cache_state.stat_calls, 2, 'initial read-and-hash must stat before and after streaming')

accepted_identity.size_low = 999
local cached_bytes, cached_digest, cached_identity, cached_reason = cache_hasher:read_and_hash_file('one-other-alias')
assert_equal(cached_reason, nil, 'same canonical path and identity must hit cache')
assert_equal(cached_bytes, 'alpha', 'cache must retain the exact accepted bytes')
assert_equal(cached_digest, accepted_digest, 'cache must retain the accepted digest')
assert_equal(cached_identity.size_low, 5, 'cache hit must return a fresh identity copy')
assert_equal(cache_state.open_calls, 1, 'cache hit must not reopen the file')
assert_equal(cache_state.stat_calls, 3, 'cache hit must still stat the current canonical path')

cached_identity.write_time_low = 999
local cached_again_bytes, _, cached_again_identity = cache_hasher:read_and_hash_file('one-alias')
assert_equal(cached_again_bytes, 'alpha', 'mutating a returned cache identity must not poison cached bytes')
assert_equal(cached_again_identity.write_time_low, 1000, 'cache must never expose its stored identity table')

local second_bytes, second_digest, _, second_reason = cache_hasher:read_and_hash_file('two-alias')
assert_equal(second_reason, nil, 'second canonical path must succeed')
assert_equal(second_bytes, 'bravo', 'canonical path must participate in the cache key')
assert_equal(second_digest, sha.sha256('bravo'), 'second canonical path must hash its own bytes')
assert_equal(cache_state.open_calls, 2, 'same stat identity on another canonical path must not reuse the first cache entry')

local wrapped_digest, wrapped_identity, wrapped_reason = cache_hasher:hash_file('two-alias')
assert_equal(wrapped_reason, nil, 'hash_file compatibility wrapper must succeed')
assert_equal(wrapped_digest, second_digest, 'hash_file must discard only bytes, not the digest')
assert_equal(wrapped_identity.size_low, 5, 'hash_file must preserve the copied stat identity')

-- If an implementation hashes one open and then reopens to obtain bytes, this
-- fixture changes the second open's same-length content and the assertion fails.
local transaction_path = 'C:\\fixture\\transaction.bin'
local transaction_identity = make_identity(5, 2000)
local transaction_state, transaction_hasher = make_fixture({
    [transaction_path] = { bytes = 'first', identity = transaction_identity },
}, nil, {
    open = function(state, path, mode)
        assert_equal(path, transaction_path, 'transaction must use canonical path')
        assert_equal(mode, 'rb', 'transaction must be binary')
        local bytes = state.open_calls == 1 and 'first' or 'later'
        local offset = 1
        return {
            read = function(_, count)
                state.read_calls = state.read_calls + 1
                if offset > #bytes then return nil end
                local value = bytes:sub(offset, offset + count - 1)
                offset = offset + #value
                return value
            end,
            close = function()
                state.close_calls = state.close_calls + 1
                return true
            end,
        }
    end,
})
local transaction_bytes, transaction_digest, _, transaction_reason = transaction_hasher:read_and_hash_file(transaction_path)
assert_equal(transaction_reason, nil, 'single read/hash transaction must succeed')
assert_equal(transaction_state.open_calls, 1, 'read-and-hash must not reopen content between hashing and returning bytes')
assert_equal(transaction_bytes, 'first', 'caller must receive the exact bytes from the hashed open')
assert_equal(transaction_digest, sha.sha256(transaction_bytes), 'accepted bytes and digest must be inseparable')

-- Every one of the four stat words must invalidate an otherwise populated cache.
for _, changed_field in ipairs(identity_fields) do
    local path = 'C:\\fixture\\invalidate-' .. changed_field .. '.bin'
    local row = { bytes = 'alpha', identity = make_identity(5, 3000) }
    local state, hasher = make_fixture({ [path] = row })
    local first_digest = assert(hasher:hash_file(path))
    assert_equal(first_digest, sha.sha256('alpha'), 'cache invalidation fixture must prime successfully')
    local opens_before = state.open_calls
    row.identity[changed_field] = row.identity[changed_field] + 1
    if changed_field == 'size_low' then
        row.bytes = 'alphax'
    end
    local digest, _, reason = hasher:hash_file(path)
    assert_equal(state.open_calls, opens_before + 1, changed_field .. ' must participate in cache identity')
    if changed_field == 'size_high' then
        assert_equal(digest, nil, 'unreadable synthetic high-size change must not be cached')
        assert_contains(reason, 'size', 'high-size mismatch must be reported after cache invalidation')
    else
        assert_equal(digest, sha.sha256(row.bytes), changed_field .. ' invalidation must hash current bytes')
    end
end

local function expect_read_failure(hasher, path, fragment, message)
    local bytes, digest, identity, reason = hasher:read_and_hash_file(path)
    assert_equal(bytes, nil, message .. ' must not return bytes')
    assert_equal(digest, nil, message .. ' must not return a digest')
    assert_equal(identity, nil, message .. ' must not return identity')
    assert_contains(reason, fragment, message)
end

-- Missing and partial stat identities must fail before any open.
do
    local state, hasher = make_fixture({}, nil, {
        stat = function() return nil, 'synthetic stat missing' end,
    })
    expect_read_failure(hasher, 'missing', 'stat', 'missing pre-read stat')
    assert_equal(state.open_calls, 0, 'missing stat must fail before open')
end

for _, missing_field in ipairs(identity_fields) do
    local identity = make_identity(3, 4000)
    identity[missing_field] = nil
    local state, hasher = make_fixture({
        ['C:\\fixture\\partial.bin'] = { bytes = 'abc', identity = identity },
    })
    expect_read_failure(hasher, 'C:\\fixture\\partial.bin', 'stat', 'partial stat missing ' .. missing_field)
    assert_equal(state.open_calls, 0, 'partial stat must fail before open')
end

for _, invalid_value in ipairs({ -1, UINT32, 1.5, '1' }) do
    local identity = make_identity(3, 4100)
    identity.write_time_high = invalid_value
    local state, hasher = make_fixture({
        ['C:\\fixture\\invalid-stat.bin'] = { bytes = 'abc', identity = identity },
    })
    expect_read_failure(hasher, 'C:\\fixture\\invalid-stat.bin', 'stat', 'non-uint32 stat word ' .. tostring(invalid_value))
    assert_equal(state.open_calls, 0, 'non-uint32 stat must fail before open')
end

do
    local path = 'C:\\fixture\\open-failure.bin'
    local state, hasher = make_fixture({
        [path] = { bytes = 'abc', identity = make_identity(3, 4200) },
    }, nil, {
        open = function() return nil, 'synthetic open failure' end,
    })
    expect_read_failure(hasher, path, 'open', 'synthetic open failure')
    assert_equal(state.open_calls, 1, 'open failure must attempt exactly one open')
end

local function synthetic_reader_fixture(label, size, reader)
    local path = 'C:\\fixture\\' .. label .. '.bin'
    local identity = make_identity(size, 5000)
    local state, hasher = make_fixture({ [path] = { bytes = '', identity = identity } }, nil, {
        open = function(state)
            return {
                read = function(_, count)
                    state.read_calls = state.read_calls + 1
                    return reader(state.read_calls, count)
                end,
                close = function()
                    state.close_calls = state.close_calls + 1
                    return true
                end,
            }
        end,
    })
    return path, state, hasher
end

do
    local path, state, hasher = synthetic_reader_fixture('early-eof', 6, function(call)
        if call == 1 then return 'abc' end
        return nil
    end)
    expect_read_failure(hasher, path, 'size', 'partial early-EOF read')
    assert_equal(state.close_calls, 1, 'early EOF failure must close the file')
    expect_read_failure(hasher, path, 'size', 'early EOF failure must never be cached')
    assert_equal(state.open_calls, 2, 'failed partial read must be retried, not cached')
end

do
    local path, state, hasher = synthetic_reader_fixture('read-failure', 6, function(call)
        if call == 1 then return 'abc' end
        return nil, 'synthetic read failure'
    end)
    expect_read_failure(hasher, path, 'read', 'synthetic read failure')
    assert_equal(state.close_calls, 1, 'read failure must close the file')
end

do
    local path, state, hasher = synthetic_reader_fixture('read-throw', 6, function(call)
        if call == 1 then return 'abc' end
        error('synthetic read exception')
    end)
    expect_read_failure(hasher, path, 'read', 'synthetic thrown read failure')
    assert_equal(state.close_calls, 1, 'thrown read failure must close the file')
end

do
    local path, state, hasher = synthetic_reader_fixture('empty-chunk', 3, function() return '' end)
    expect_read_failure(hasher, path, 'read', 'empty synthetic read chunk')
    assert_equal(state.read_calls, 1, 'empty read chunk must fail instead of looping')
end

-- A change to any exact stat word during streaming rejects the transaction.
for _, changed_field in ipairs(identity_fields) do
    local path = 'C:\\fixture\\post-change-' .. changed_field .. '.bin'
    local before = make_identity(3, 6000)
    local after = copy_identity(before)
    after[changed_field] = after[changed_field] + 1
    local state, hasher = make_fixture({ [path] = { bytes = 'abc', identity = before } }, nil, {
        stat = function(state)
            if state.stat_calls == 1 then return copy_identity(before) end
            return copy_identity(after)
        end,
    })
    expect_read_failure(hasher, path, 'changed', 'post-read change to ' .. changed_field)
    assert_equal(state.open_calls, 1, 'changed file must be opened once')
    assert_equal(state.close_calls, 1, 'changed file must still be closed')
end

print('accessxi SHA-256 tests passed')
