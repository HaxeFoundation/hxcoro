import haxe.Exception;
import haxe.Int64;
import haxe.io.Bytes;
import cpp.Char;
import cpp.Pointer;
import cpp.encoding.Utf8;

using cpp.marshal.ViewExtensions;

/**
	Minimal externs for the parts of SDL3 that this example uses.
**/
@:semantics(value)
@:include("SDL3/SDL.h")
@:cpp.PointerType({ type : "SDL_Window" })
extern class Window {}

@:semantics(value)
@:include("SDL3/SDL.h")
@:cpp.PointerType({ type : "SDL_Renderer" })
extern class Renderer {}

@:semantics(value)
@:include("SDL3/SDL.h")
@:cpp.ValueType({ type : "SDL_FRect" })
extern class FRect {
	var x : cpp.Float32;
	var y : cpp.Float32;
	var w : cpp.Float32;
	var h : cpp.Float32;

	function new() : Void;
}

@:semantics(value)
@:include("SDL3/SDL.h")
@:cpp.ValueType({ type : "SDL_UserEvent" })
extern class UserEvent {
	var data1 : Pointer<cpp.Void>;

	function new() : Void;
}

@:semantics(value)
@:include("SDL3/SDL.h")
@:cpp.ValueType({ type : "SDL_MouseButtonEvent" })
extern class MouseButtonEvent {
	var x : cpp.Float32;
	var y : cpp.Float32;
}

@:semantics(value)
@:include("SDL3/SDL.h")
@:cpp.ValueType({ type : "SDL_KeyboardEvent" })
extern class KeyboardEvent {
	var key : Int;
}

@:semantics(value)
@:include("SDL3/SDL.h")
@:cpp.ValueType({ type : "SDL_Event" })
extern class Event {
	var type : Int;

	var user : UserEvent;

	var button : MouseButtonEvent;

	var key : KeyboardEvent;

	function new() : Void;
}

@:include("SDL3/SDL.h")
@:buildXml("
<copyFile name='SDL3.dll' from='${SDL_DIST_DIR}/lib/x64' if='windows'/>

<files id='haxe'>
	<compilerflag value='-I${SDL_DIST_DIR}/include' if='SDL_DIST_DIR'/>
</files>

<linker id='exe'>
	<lib name='${SDL_DIST_DIR}/lib/x64/SDL3.lib' if='windows'/>
	<lib name='-lSDL3' unless='windows'/>
</linker>
")
extern class SDL {
	static inline final INIT_VIDEO : Int = 0x20;

	static inline final WINDOW_RESIZABLE : Int = 0x20;

	static inline final EVENT_QUIT : Int = 0x100;

	static inline final EVENT_KEY_DOWN : Int = 0x300;

	static inline final EVENT_MOUSE_BUTTON_DOWN : Int = 0x401;

	static inline final KEY_ESCAPE : Int = 0x1b;

	static inline final KEY_SPACE : Int = 0x20;

	@:native("SDL_Init")
	static function init(flags:Int):Bool;

	@:native("SDL_Quit")
	static function quit():Void;

	static inline function createWindow(title:String, width:Int, height:Int, flags:Int64):Window {
		return createWindowImpl(toCString(title).asView().reinterpret().ptr, width, height, flags);
	}

	@:native("SDL_DestroyWindow")
	static function destroyWindow(window:Window):Void;

	static inline function setWindowTitle(window:Window, title:String):Bool {
		return setWindowTitleImpl(window, toCString(title).asView().reinterpret().ptr);
	}

	@:native("SDL_CreateRenderer")
	static function createRenderer(window:Window, name:Pointer<Char>):Renderer;

	@:native("SDL_DestroyRenderer")
	static function destroyRenderer(renderer:Renderer):Void;

	@:native("SDL_SetRenderVSync")
	static function setRenderVSync(renderer:Renderer, vsync:Int):Bool;

	@:native("SDL_SetRenderDrawColor")
	static function setRenderDrawColor(renderer:Renderer, r:Int, g:Int, b:Int, a:Int):Bool;

	@:native("SDL_RenderClear")
	static function renderClear(renderer:Renderer):Bool;

	@:native("SDL_RenderFillRect")
	static function renderFillRect(renderer:Renderer, rect:FRect):Bool;

	@:native("SDL_RenderPresent")
	static function renderPresent(renderer:Renderer):Bool;

	@:native("SDL_RegisterEvents")
	static function registerEvents(number:Int):Int;

	@:native("SDL_PushEvent")
	static function pushEvent(event:Event):Bool;

	@:native("SDL_PollEvent")
	static function pollEvent(event:Event):Bool;

	@:native("SDL_Delay")
	static function delay(ms:Int):Void;

	//

	@:native("SDL_CreateWindow")
	private static function createWindowImpl(title:Pointer<Char>, width:Int, height:Int, flags:Int64):Window;

	@:native("SDL_SetWindowTitle")
	private static function setWindowTitleImpl(window:Window, title:Pointer<Char>):Bool;

	private static inline function toCString(s:String) {
		final size  = Utf8.getByteCount(s);
		final bytes = Bytes.alloc(Int64.toInt(size) + 1);

		if (Utf8.encode(s, bytes.asView()) != size) {
			throw new Exception("Failed to encode the entire string");
		}

		return bytes;
	}
}
