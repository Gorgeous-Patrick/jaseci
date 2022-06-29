walker test {
	can bi_enc.set_model_config;
	root {
		for i in range(100) {
			bi_enc.set_model_config({"model_name":"JACBIENC"});
		}
	}
}