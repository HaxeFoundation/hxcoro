package hxcoro.schedulers;

import hxcoro.ds.Out;
import haxe.Timer;
import haxe.Int64;
import haxe.coro.Mutex;
import haxe.coro.schedulers.Scheduler;
import haxe.coro.schedulers.IScheduleObject;
import haxe.coro.schedulers.ISchedulerHandle;
import haxe.exceptions.ArgumentException;

private typedef Lambda = () -> Void;

private class Event implements ISchedulerHandle {
	public var call:Null<Lambda>;
	public var next:Null<Event>;

	public function new(call:() -> Void) {
		this.call = call;
		this.next = null;
	}

	public function close() {
		call = null;
	}
}

private class ScheduledEvent {
	public final runTime:Int64;
	public var head:Null<Event>;
	public var tail:Null<Event>;

	public function new(runTime:Int64, event:Event) {
		this.runTime = runTime;
		this.head = event;
		this.tail = event;
	}

	public function append(event:Event) {
		tail.next = event;
		tail = event;
	}

	public function run() {
		var e = head;
		while (null != e) {
			if (e.call != null) {
				e.call();
			}

			e = e.next;
		}
	}
}

private class Node {
	public var key:ScheduledEvent;
	public var left:Null<Node>;
	public var right:Null<Node>;

	public function new(key:ScheduledEvent) {
		this.key = key;
		this.left = null;
		this.right = null;
	}
}

private class BinarySearchTree {
	private var root:Null<Node>;

	public function new() {
		root = null;
	}

	/**
	 * Attempts to insert and event into the BST at the specified time.
	 * @param out Contains either the newly created scheduled event on a successful insertion,
	 * or the existing scheduled event if insertion failed.
	 * @return True if the event was added, false if there was already a node in the tree at that time.
	 */
	public function tryInsert(key:Int64, event:Event, out:Out<ScheduledEvent>):Bool {
		if (null == root) {
			final o = new ScheduledEvent(key, event);

			root = new Node(o);

			out.set(o);

			return true;
		}

		var current = root;
		do {
			if (current.key.runTime == key) {
				out.set(current.key);

				return false;
			}

			if (current.key.runTime > key && null != current.left) {
				current = current.left;
			} else if (current.key.runTime < key && null != current.right) {
				current = current.right;
			} else {
				break;
			}
		} while (null != current);

		final o = new ScheduledEvent(key, event);

		out.set(o);

		if (current.key.runTime > key) {
			current.left = new Node(o);
		} else {
			current.right = new Node(o);
		}

		return true;
	}

	public function find(key:Int64):Null<ScheduledEvent> {
		if (null == root) {
			return null;
		}

		var searching = root;
		while (null != searching) {
			if (searching.key.runTime == key) {
				return searching.key;
			}

			if (key > searching.key.runTime) {
				searching = root.right;
			} else {
				searching = root.left;
			}
		}

		return null;
	}

	public function delete(key:Int64) {
		if (null == root) {
			return;
		}

		doDelete(root, key);
	}

	private function doDelete(node:Node, key:Int64) {
		if (null == node) {
			return node;
		}

		if (node.key.runTime > key) {
			node.left = doDelete(node.left, key);
		} else if (node.key.runTime < key) {
			node.right = doDelete(node.right, key);
		} else {
			if (null == node.left) {
				return node.right;
			}
			if (null == node.right) {
				return node.left;
			}

			final s = successor(node);
			node.key = s.key;
			node.right = doDelete(node.right, s.key.runTime);
		}

		return node;
	}

	private function successor(current:Node) {
		current = current.right;
		while (null != current && null != current.left) {
			current = current.left;
		}

		return current;
	}
}

private class MinimumHeap {
	final storage:Array<ScheduledEvent>;

	public function new() {
		storage = [];
	}

	public function left(i:Int) {
		return (i << 1) + 1;
	}

	public function right(i:Int) {
		return (i << 1) + 2;
	}

	public function parent(i:Int) {
		return (i - 1) >> 1;
	}

	public function minimum() {
		if (storage.length == 0) {
			return null;
		}

		return storage[0];
	}

	public function insert(event:ScheduledEvent) {
		storage.push(event);

		var i = storage.length - 1;
		while (i > 0 && storage[parent(i)].runTime > storage[i].runTime) {
			final p = parent(i);

			swap(i, p);

			i = p;
		}
	}

	public function extract() {
		if (storage.length == 0) {
			return null;
		}

		if (storage.length == 1) {
			return storage.pop();
		}

		final root = minimum();
		storage[0] = storage[storage.length - 1];
		storage.pop();

		heapify(0);

		return root;
	}

	function swap(fst:Int, snd:Int) {
		final temp = storage[fst];
		storage[fst] = storage[snd];
		storage[snd] = temp;
	}

	function heapify(index:Int) {
		while (true) {
			final l = left(index);
			final r = right(index);

			var smallest = index;
			if (l < storage.length && storage[l].runTime < storage[smallest].runTime) {
				smallest = l;
			}
			if (r < storage.length && storage[r].runTime < storage[smallest].runTime) {
				smallest = r;
			}

			if (smallest != index) {
				swap(index, smallest);
				index = smallest;
			} else {
				break;
			}
		}
	}
}

class EventLoopScheduler extends Scheduler {
	final futureMutex:Mutex;
	final heap:MinimumHeap;
	final bst:BinarySearchTree;
	final out:Out<ScheduledEvent>;

	public function new() {
		super();

		futureMutex = new Mutex();
		heap = new MinimumHeap();
		bst = new BinarySearchTree();
		out = new Out();
	}

	public function schedule(ms:Int64, func:() -> Void):ISchedulerHandle {
		if (ms < 0) {
			throw new ArgumentException("Time must be greater or equal to zero");
		}

		final event = new Event(func);

		futureMutex.acquire();

		if (bst.tryInsert(now() + ms, event, out)) {
			heap.insert(out.get());
		} else {
			out.get().append(event);
		}

		futureMutex.release();

		return event;
	}

	public function scheduleObject(obj:IScheduleObject) {
		schedule(0, () -> obj.onSchedule());
	}

	public function now() {
		return Timer.milliseconds();
	}

	public function run() {
		final currentTime = now();

		while (true) {
			futureMutex.acquire();
			final minimum = heap.minimum();
			if (minimum == null || minimum.runTime > currentTime) {
				break;
			}

			final extracted = heap.extract();

			bst.delete(extracted.runTime);

			extracted.run();

			futureMutex.release();
		}

		futureMutex.release();
	}

	public function toString() {
		return '[EventLoopScheduler]';
	}
}