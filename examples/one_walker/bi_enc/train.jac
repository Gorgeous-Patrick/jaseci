walker test {
	can bi_enc.train;
	root {
		for i in range(100) {
			bi_enc.train({"item": "Hello"},True,{"item": "Hello"});
		}
	}
}