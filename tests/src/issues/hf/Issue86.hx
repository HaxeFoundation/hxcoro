package issues.hf;

import hxcoro.ds.channels.Channel;

class Issue86 extends atest.Test {
	function test() {
		final channel = Channel.createUnbounded({});
		final numTasks = 50;
		run(node -> {
			for (i in 0...numTasks) {
				node.async(node -> {
					channel.write(1);
				});
			}
		});
		Assert.pass();
	}
}