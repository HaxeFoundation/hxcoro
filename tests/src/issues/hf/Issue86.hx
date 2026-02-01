package issues.hf;

import hxcoro.ds.channels.Channel;

class Issue86 extends utest.Test {
	function test() {
		final channel = Channel.createUnbounded({});
		final numTasks = 50;
		CoroRun.runScoped(node -> {
			for (i in 0...numTasks) {
				node.async(node -> {
					channel.write(1);
				});
			}
		});
		Assert.pass();
	}
}