package ds;

import hxcoro.ds.CircularBuffer;
import hxcoro.ds.Out;

class TestCircularBuffer extends atest.Test {
	/**
		Removed items used to stay in their slots until a later push overwrote them, so a drained
		bounded channel kept up to its capacity of items alive.
	**/
	function testPopClearsSlot() {
		final buffer = new CircularBuffer<Array<Int>>(2);
		// Read as `Dynamic`, because on the JVM the storage of a type parameter is an `Object[]`.
		final storage:haxe.ds.Vector<Dynamic> = cast @:privateAccess buffer.storage;
		final out = new Out();
		buffer.tryPush([1]);
		buffer.tryPopTail(out);
		Assert.isNull(storage[0], "tryPopTail kept the item");
		buffer.tryPush([2]);
		buffer.tryPopHead(out);
		Assert.isNull(storage[1], "tryPopHead kept the item");
	}

	function testPopReturnsItems() {
		final buffer = new CircularBuffer<Int>(3);
		final out = new Out();
		for (i in 1...4) {
			Assert.isTrue(buffer.tryPush(i));
		}
		Assert.isFalse(buffer.tryPush(4));
		Assert.isTrue(buffer.tryPopTail(out));
		Assert.equals(1, out.get());
		Assert.isTrue(buffer.tryPopHead(out));
		Assert.equals(3, out.get());
		Assert.isTrue(buffer.tryPopTail(out));
		Assert.equals(2, out.get());
		Assert.isTrue(buffer.wasEmpty());
		// Cleared slots are reused.
		Assert.isTrue(buffer.tryPush(5));
		Assert.isTrue(buffer.tryPopTail(out));
		Assert.equals(5, out.get());
	}
}
