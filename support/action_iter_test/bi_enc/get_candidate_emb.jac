walker get_candidate_emb {
	can bi_enc.get_candidate_emb;
	root {
		for i=0 to i<500 by i+=1 {
			bi_enc.get_candidate_emb("Hello");
		}
	}
}