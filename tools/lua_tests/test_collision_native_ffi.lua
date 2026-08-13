local ffi = require('ffi')

ffi.cdef[[
    #pragma pack(push, 4)
    typedef struct AXICollisionPackedLoadStatus {
        unsigned int struct_size;
        int state;
        unsigned int zone_id;
        unsigned int progress_percent;
        unsigned long long generation;
        char message[256];
        char dat_sha256[65];
        char settings_sha256[65];
    } AXICollisionPackedLoadStatus;
    #pragma pack(pop)

    unsigned int __cdecl AXI_GetAbiVersion(void);
    void* __cdecl AXI_CreateContext(void);
    void __cdecl AXI_DestroyContext(void* context);
    int __cdecl AXI_PollLoadZone(
        void* context,
        unsigned long long generation,
        AXICollisionPackedLoadStatus* status);
]]

local dll_path = os.getenv('ACCESSXI_COLLISION_DLL')
assert(type(dll_path) == 'string' and dll_path ~= '',
    'ACCESSXI_COLLISION_DLL must name the x86 collision DLL')

local native = ffi.load(dll_path)
assert(ffi.sizeof('AXICollisionPackedLoadStatus') == 412,
    'explicit four-byte status layout changed')

local context = native.AXI_CreateContext()
assert(context ~= nil and context ~= ffi.NULL, 'collision context creation failed')

local status = ffi.new('AXICollisionPackedLoadStatus[1]')
status[0].struct_size = ffi.sizeof('AXICollisionPackedLoadStatus')
local result = tonumber(native.AXI_PollLoadZone(context, 0, status))
native.AXI_DestroyContext(context)

assert(result == 0,
    ('packed LuaJIT status buffer was rejected with native result %s'):format(tostring(result)))
assert(tonumber(native.AXI_GetAbiVersion()) == 3,
    'collision native ABI must identify the explicitly packed status layout')
assert(tonumber(status[0].generation) == 0, 'initial generation was not returned')
assert(tonumber(status[0].state) == 0, 'new context did not report idle state')

print('collision native LuaJIT FFI ABI test passed')
