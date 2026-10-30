import SDL;
import haxe.Timer;
import haxe.coro.dispatchers.Dispatcher;
import haxe.exceptions.CancellationException;
import hxcoro.Coro.*;
import hxcoro.CoroRun;
import hxcoro.dispatchers.ThreadPoolDispatcher;
import hxcoro.ds.channels.Channel;
import hxcoro.exceptions.TimeoutException;
import hxcoro.schedulers.RealTimeScheduler;
import hxcoro.task.ICoroNode;
import hxcoro.thread.FixedThreadPool;

using hxcoro.run.ContextRun;
using hxcoro.util.Convenience;

/**
	Input that the main loop forwards to the coroutines.
**/
enum Input {
	Click(x:Float, y:Float);
	ClearBoxes;
	CountPrimes;
}

/**
	A square that the main loop draws. Boxes are only accessed on the main thread, so they
	need no synchronization.
**/
class Box {
	public var x:Float;
	public var y:Float;
	public var size:Float;
	public final color:Int;

	public function new(x, y, color) {
		this.x = x;
		this.y = y;
		this.size = 0;
		this.color = color;
	}
}

/**
	The coroutine side of the example. It doesn't call SDL itself, but only updates state
	that the main loop shows.
**/
class App {
	public final boxes:Array<Box>;
	public final input:Channel<Input>;

	/**
		The new window title, if it changed since the main loop last applied it.
	**/
	public var title:Null<String>;

	final background:Dispatcher;

	public function new(background) {
		this.background = background;
		boxes = [];
		input = Channel.createUnbounded({});
	}

	/**
		Handles input until the task running this is cancelled.
	**/
	@:coroutine public function run(node:ICoroNode) {
		// The box animations are children of this scope, so that they can be cancelled together.
		scope(animations -> {
			for (input in input) {
				switch (input) {
					case Click(x, y):
						animations.async(_ -> animateBox(x, y));
					case ClearBoxes:
						animations.cancelChildren();
					case CountPrimes:
						node.async(node -> countPrimes(node));
				}
			}
		});
	}

	/**
		Shows a pulsing box at `x`, `y` for three seconds.
	**/
	@:coroutine function animateBox(x:Float, y:Float) {
		final box = new Box(x, y, Std.random(0xFFFFFF));
		boxes.push(box);
		try {
			timeout(3000, _ -> {
				final start = Timer.stamp();
				while (true) {
					final t = Timer.stamp() - start;
					box.size = 40 + 15 * Math.sin(t * 8);
					box.y = y - 30 * t;
					delay(16);
				}
			});
		} catch (_:TimeoutException) {
			// The box's time is up.
		} catch (e:CancellationException) {
			// Cancelled by Escape or by quitting.
			boxes.remove(box);
			throw e;
		}
		boxes.remove(box);
	}

	/**
		Counts primes on the background dispatcher, so that the main loop keeps running, and
		then shows the result in the window title.
	**/
	@:coroutine function countPrimes(node:ICoroNode) {
		final limit = 3_000_000;
		title = 'Counting primes below $limit...';
		final start = Timer.stamp();
		final count = node.with(background).async(worker -> {
			var count = 0;
			for (i in 2...limit) {
				// A loop that doesn't suspend has to check for cancellation itself.
				if (i % 10000 == 0 && worker.context.isCancellationRequested()) {
					break;
				}
				if (isPrime(i)) {
					count++;
				}
			}
			count;
		}).await();
		// Back on the main thread here, so there is no race with the main loop.
		final ms = Std.int((Timer.stamp() - start) * 1000);
		title = 'There are $count primes below $limit (took ${ms}ms)';
	}

	static function isPrime(n:Int) {
		var i = 2;
		while (i * i <= n) {
			if (n % i == 0) {
				return false;
			}
			i++;
		}
		return true;
	}
}

function main() {
	SDL.init(SDL.INIT_VIDEO);

	final window   = SDL.createWindow("hxcoro + SDL: click, Escape, Space", 1280, 720, SDL.WINDOW_RESIZABLE);
	final renderer = SDL.createRenderer(window, null);
	SDL.setRenderVSync(renderer, 1);

	// The main loop drives this scheduler. It is shared by both dispatchers, which works
	// because a due event is dispatched on the dispatcher of the coroutine that waits for it.
	final scheduler  = new RealTimeScheduler();
	final dispatcher = new SdlDispatcher(scheduler);
	final pool       = new FixedThreadPool(4);
	final background = new ThreadPoolDispatcher(scheduler, pool);

	final app  = new App(background);
	final task = CoroRun.with(dispatcher).launchTask(node -> app.run(node));

	final event = new Event();
	final rect  = new FRect();
	while (task.isActive()) {
		// Dispatches the coroutines whose delays are over. This pushes SDL events, which
		// are handled right below.
		scheduler.loop(NoWait);

		while (SDL.pollEvent(event)) {
			switch (event.type) {
				case SDL.EVENT_QUIT:
					// Cancels everything. The loop keeps running until all tasks have finished.
					task.cancel();
				case SDL.EVENT_MOUSE_BUTTON_DOWN:
					app.input.tryWrite(Click(event.button.x, event.button.y));
				case SDL.EVENT_KEY_DOWN if (event.key.key == SDL.KEY_ESCAPE):
					app.input.tryWrite(ClearBoxes);
				case SDL.EVENT_KEY_DOWN if (event.key.key == SDL.KEY_SPACE):
					app.input.tryWrite(CountPrimes);
				case type if (type == dispatcher.eventType):
					dispatcher.run(event);
				case _:
			}
		}

		final title = app.title;
		if (title != null) {
			SDL.setWindowTitle(window, title);
			app.title = null;
		}

		SDL.setRenderDrawColor(renderer, 20, 20, 30, 255);
		SDL.renderClear(renderer);
		for (box in app.boxes) {
			SDL.setRenderDrawColor(renderer, box.color >> 16, (box.color >> 8) & 0xFF, box.color & 0xFF, 255);
			rect.x = box.x - box.size / 2;
			rect.y = box.y - box.size / 2;
			rect.w = box.size;
			rect.h = box.size;
			SDL.renderFillRect(renderer, rect);
		}
		// Waits for the next frame because of vsync.
		SDL.renderPresent(renderer);
	}

	pool.shutDown(true);
	SDL.destroyRenderer(renderer);
	SDL.destroyWindow(window);
	SDL.quit();
}
