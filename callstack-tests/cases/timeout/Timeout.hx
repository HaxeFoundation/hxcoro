package timeout;

import hxcoro.exceptions.TimeoutException;
import hxcoro.run.Setup;
using hxcoro.run.ContextRun;

/**
	A coroutine that loops with `delay(1)` inside a `timeout(5, ...)` call.
	When the virtual-time scheduler advances past 5 ms, `timeout` cancels the
	inner scope and throws `TimeoutException` back to the caller.

	Tests that the `timeout()` call-site frame and its outer task-creation chain
	appear correctly in the exception stack.
**/
function entry() {
	Setup.createVirtualTrampoline().createContext().runTask(node -> {
		final task1 = node.async(node -> {
			timeout(5, _ -> {
				while (true) {
					delay(1);
				}
			});
		});
		task1.await();
	});
}
