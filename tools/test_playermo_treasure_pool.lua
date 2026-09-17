-- Captured self command IDs: 5,8,7,25,9,19,12,10 with a treasure pool;
-- the pool's optional ID12 disappears, while Check remains ID10.
local addon=assert(arg[1],'pass the addon root')
local f=assert(io.open(addon..'/accessxi_reader.lua','rb'));local source=f:read('*a');f:close()
local obj,child,entry=0x251A8DB8,0x25199E80,0x25393D48
local u16,u32,logs={},{},{}
u32[obj+8]=entry;u32[entry+0xC]=0x1E50F2EC
local labels={
 ['ROM\\165\\76.DAT:73:label']='Treasure Pool',
 ['ROM\\165\\75.DAT:300:help']='Cast lots on the treasure you want.',
 ['ROM\\165\\74.DAT:122:label']='Check',
 ['ROM\\165\\75.DAT:30:help']="Estimate target's relative strength.",
 ['ROM\\165\\76.DAT:10:label']='Trade',
 ['ROM\\165\\75.DAT:38:help']='Trade with target.',
 ['ROM\\165\\76.DAT:129:label']='Chat',
 ['ROM\\165\\75.DAT:22:help']='Chat with target.',
 ['ROM\\165\\75.DAT:718:help']='Cast Trust magic.',
}
local axi={
 is_probe_pointer=function(p) return type(p)=='number' and p>=0x10000 end,
 plain_native_menu_label=function(s)return s end,
 plain_native_menu_help=function(s)return s end,
 dat_index_row_text=function(p,r,k)return labels[p..':'..r..':'..k] or '' end,
 auto_translate_label=function()return '' end,
 playermo_target_state_context=function()return {kind='self'} end,
 playermo_native_help_entry=function()return nil,'none',0,0,'','' end,
 speech_output_text=function(s)return s end,
 escape_probe_log_text=tostring,
 native_query_label_for_selection=function()error('Self commands must not reach generic text-pointer query')end,
 format_probe_index_fields=function()return '' end,
 format_probe_dwords=function()return '' end,
 status_menu_probe_inline_strings=function()return '' end,
}
local methods={append=function(t,s)t[#t+1]=s end,concat=table.concat}
local env={
 accessxi=axi,T=function(t)return setmetatable(t,{__index=methods})end,
 read_u16=function(p)return u16[p] end,read_u32=function(p)return u32[p] end,
 tick=function()return 100 end,
 safe_call=function(fn,d)local ok,r=pcall(fn);if ok then return r else return d end end,
 AshitaCore={GetMemoryManager=function()return {GetTarget=function()return nil end}end},
 log_state=function(s)logs[#logs+1]=s end,
}
setmetatable(env,{__index=_G});string.fmt=string.format;string.eq=function(a,b)return a==b end
local function load_function(name)
 local a=assert(source:find('function accessxi.'..name..'(',1,true))
 local b=assert(source:find('\nfunction ',a+10,true))
 if name=='playermo_menu_speech' then b=assert(source:find('\naccessxi.inspect_equipment_slot_names',a,true)) end
 local fn=assert(loadstring(source:sub(a,b-1)));setfenv(fn,env);fn()
end
for _,name in ipairs({'playermo_dynamic_command_id','playermo_command_id_dat_entry','playermo_command_menu_dat_entry','playermo_command_context_label','playermo_menu_speech'}) do load_function(name) end
local function setup(ids)
 u16[obj+0x58]=#ids
 for i=1,12 do u16[child+0x1A+i*2]=ids[i] or 0 end
end
local function speech(selected)
 u16[obj+0x4C]=selected
 return axi.playermo_menu_speech('menu    playermo','Player',obj,selected,12,0,0,child,entry)
end
-- Reproduces the user's bug on the previous implementation: row7 said Treasure Pool.
setup({5,8,7,25,9,19,10})
local check=speech(7)
assert(check=='Commands. Check. '..labels['ROM\\165\\75.DAT:30:help'],tostring(check))
assert(logs[#logs]:find('commandId=10',1,true),'Automatic diagnostics must identify the selected native command')
setup({5,8,7,25,9,19,12,10})
assert(speech(7)=='Commands. Treasure Pool. Cast lots on the treasure you want.')
assert(speech(8)=='Commands. Check. '..labels['ROM\\165\\75.DAT:30:help'])
-- Additional conditional commands may also disappear; their identity still wins.
setup({5,8,7,9,19,12,10})
assert(speech(6)=='Commands. Treasure Pool. Cast lots on the treasure you want.')
assert(speech(7)=='Commands. Check. '..labels['ROM\\165\\75.DAT:30:help'])
setup({5,8,7,25,9,19,10})
u16[child+0x1A+8*2]=12
assert(speech(8)==nil,'Do not read a stale command beyond the visible list')
u16[child+0x1A+7*2]=0
assert(speech(7)==nil,'Missing command identity must not fall back to row-number guessing')
assert(axi.playermo_command_menu_dat_entry(7,0,12)==nil,'Require a native command record')
assert(axi.playermo_command_menu_dat_entry(7,0x1E50F2EC,99)==nil,'Do not invent unknown command IDs')
labels['ROM\\165\\76.DAT:73:label']='';labels['ROM\\165\\75.DAT:300:help']=''
assert(axi.playermo_command_menu_dat_entry(7,0x1E50F2EC,12)==nil,'Require actual DAT text')
print('Self command production reader follows native IDs with Treasure Pool present, absent or shifted')
