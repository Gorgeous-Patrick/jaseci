walker test {
	can bi_enc.load_model;
	root {
		for i in range(100) {
			bi_enc.load_model("/dev/null");
		}
	}
}