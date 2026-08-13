local reader_path = assert(arg[1], 'expected accessxi_reader.lua path')
local file = assert(io.open(reader_path, 'rb'))
local source = assert(file:read('*a'))
file:close()

local start_marker = "accessxi.load_code_module('recorded_survey_navigation'"
local end_marker = "accessxi.load_code_module('metalworks_elevator_navigation'"
local first = assert(source:find(start_marker, 1, true), 'recorded-survey reader block is missing')
local last = assert(source:find(end_marker, first + #start_marker, true),
    'recorded-survey reader block end is missing')
local block = source:sub(first, last - 1)

local list_methods = {}
function list_methods:len() return #self end
function list_methods:append(value) self[#self + 1] = value end
function list_methods:clear() for index = #self, 1, -1 do self[index] = nil end end
function T(value) return setmetatable(value or {}, { __index = list_methods }) end

local module_loads = 0
local survey_reads = 0
accessxi = {}
function accessxi.load_code_module(name, _environment)
    assert(name == 'recorded_survey_navigation', 'reader loaded the wrong module')
    module_loads = module_loads + 1
    function accessxi.nav_recorded_survey_load()
        survey_reads = survey_reads + 1
        return true
    end
end

function nav_distance() return 0 end
function nav_split_tsv() return T({}) end
function nav_clean_field(value) return tostring(value or '') end
function log_line() end

local chunk, reason = loadstring(block, '@recorded-survey-reader-lifecycle')
assert(chunk, reason)
chunk()

assert(module_loads == 1, 'reader must register the recorded-survey route module')
assert(survey_reads == 0,
    'reader startup must not synchronously parse the 6,499-node recorded survey')
assert(accessxi.nav_recorded_survey_load() == true and survey_reads == 1,
    'the recorded survey must remain available for its first route request')

print('recorded survey reader lifecycle tests passed')
