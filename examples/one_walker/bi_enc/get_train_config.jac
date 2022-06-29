walker test {
	can bi_enc.get_train_config;
	root {
		for i in range(100) {
			bi_enc.get_train_config();
		}
	}
}