walker test {
	can bi_enc.get_model_config;
	root {
		for i in range(100) {
			bi_enc.get_model_config();
		}
	}
}