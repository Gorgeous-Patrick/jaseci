walker test {
	can bi_enc.set_train_config;
	root {
		for i in range(100) {
			bi_enc.set_train_config({"train_batch_size":8});
		}
	}
}