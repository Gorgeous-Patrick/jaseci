walker test {
	can bi_enc.save_model;
	root {
		for i in range(100) {
			bi_enc.save_model("/dev/null");
		}
	}
}