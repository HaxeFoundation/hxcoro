package hxcoro.lua;

/**
	Patches the Haxe Lua runtime `_hx_bit` table with native Lua 5.4 bitwise
	operators when running in `-D lua-vanilla` mode.

	Background: The Haxe Lua target generates all bitwise operations (<<, >>, &,
	|, ^, ~) as calls through a `_hx_bit` table. That table is populated at
	startup by trying to load the `bit32` library (Lua 5.2/5.3) or the `bit`
	library (LuaJIT). When neither is available — which is the case on Lua 5.4
	with `-D lua-vanilla` — the table falls back to an error-raising stub.

	Lua 5.4 has native bitwise operators built in, so there is no need for
	external libraries. This class patches `_hx_bit` with native-operator
	implementations in place of the stub.

	Must be force-included in the build via
	`--macro include("hxcoro.lua.LuaVanillaBitPatch")`.
**/
#if (lua && lua_vanilla)
class LuaVanillaBitPatch {
	static function __init__() {
		// _hx_bit_raw is nil when neither bit32 (Lua 5.2/5.3) nor bit (LuaJIT) was loaded.
		// In that case _hx_bit is an error-raising stub; replace its entries with
		// native Lua 5.4 bitwise operators.
		untyped __lua__("if not _hx_bit_raw then\n  local i32 = function(v) return (v & 0x7FFFFFFF) - (v & 0x80000000) end\n  _hx_bit.band    = function(a, b) return i32(a & b) end\n  _hx_bit.bor     = function(a, b) return i32(a | b) end\n  _hx_bit.bxor    = function(a, b) return i32(a ~ b) end\n  _hx_bit.bnot    = function(a)    return i32(~a) end\n  _hx_bit.lshift  = function(a, b) return i32(a << b) end\n  _hx_bit.rshift  = function(a, b) return i32((a & 0xFFFFFFFF) >> b) end\n  _hx_bit.arshift = function(a, b)\n    if b == 0 then return a end\n    if b >= 32 then return (a < 0) and -1 or 0 end\n    local ua = a & 0xFFFFFFFF\n    local r = ua >> b\n    if a & 0x80000000 ~= 0 then r = r | (0xFFFFFFFF << (32 - b)) end\n    return i32(r)\n  end\nend");
	}
}
#end
