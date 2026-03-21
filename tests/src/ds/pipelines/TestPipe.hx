package ds.pipelines;

import hxcoro.dispatchers.TrampolineDispatcher;
import hxcoro.schedulers.VirtualTimeScheduler;
import haxe.io.Bytes;
import hxcoro.ds.Out;
import haxe.exceptions.ArgumentException;
import hxcoro.ds.pipelines.Pipe;
import atest.Test;
import haxe.io.UInt8Array;
import haxe.io.ArrayBufferView;

private class Packet {
	public static final HEADER_SIZE = 4;
	public static final MAX_ENCODED_SIZE = 260;
	public static final MIN_ENCODED_SIZE = HEADER_SIZE;

	public final src : Int;

	public final dst : Int;

	public final payload : Bytes;

	public function new(src, dst, payload) {
		this.src     = src;
		this.dst     = dst;
		this.payload = payload;
	}

	public function encode(view:ArrayBufferView) {
		final writer = UInt8Array.fromData(view.getData());

		writer[0] = 0xFF;
		writer[1] = src;
		writer[2] = dst;
		writer[3] = payload.length;

		for (i in 0...payload.length) {
			writer[HEADER_SIZE + i] = payload.get(i);
		}

		return HEADER_SIZE + payload.length;
	}

	public function equals(other:Packet) {
		return src == other.src && dst == other.dst && payload.compare(other.payload) == 0;
	}

	public static function decode(view:ArrayBufferView, packet:Out<Packet>, count:Out<Int>) {
		final reader = UInt8Array.fromData(view.getData());
		final magic  = reader[0];
		final src    = reader[1];
		final dst    = reader[2];
		final size   = reader[3];

		if (reader.length < HEADER_SIZE + size) {
			return false;
		}

		final payload = Bytes.alloc(size);
		for (i in 0...size) {
			payload.set(i, reader[HEADER_SIZE + i]);
		}

		packet.set(new Packet(src, dst, payload));
		count.set(HEADER_SIZE + size);

		return true;
	}
}

class TestPipe extends Test {
	function test_general() {
		final count      = 100;
		final input      = [ for (_ in 0...count) new Packet(Std.random(10), Std.random(10), Bytes.alloc(Std.random(256))) ];
		final output     = [];
		final scheduler  = new VirtualTimeScheduler();
		final dispatcher = new TrampolineDispatcher(scheduler);
		final task       = CoroRun.with(dispatcher).createTask(scope -> {
			final pipe = Pipe.create();

			scope.async(_ -> {
				for (packet in input) {
					final buffer = pipe.writer.getBuffer(Packet.MAX_ENCODED_SIZE);
					final count  = packet.encode(buffer);

					pipe.writer.advance(count);
					pipe.writer.flush();
				}

				pipe.writer.close();
			});

			scope.async(_ -> {
				final out    = new Out();
				final packet = new Out();
				final count  = new Out();

				while (pipe.reader.waitForRead()) {
					while (pipe.reader.tryReadAtLeast(Packet.MIN_ENCODED_SIZE, out)) {
						final buffer = out.get();

						if (Packet.decode(buffer, packet, count)) {
							output.push(packet.get());

							pipe.reader.advance(count.get(), 0);
						} else {
							pipe.reader.advance(0, buffer.byteLength);
						}
					}
				}
			});
		});

		task.start();
		scheduler.advanceBy(1);

		if (Assert.equals(input.length, output.length)) {
			for (i in 0...count) {
				Assert.isTrue(input[i].equals(output[i]));
			}
		}
	}
}