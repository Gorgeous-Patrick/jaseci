walker entity_detection {
	can ent_ext.entity_detection;
	root {
		for i=0 to i<100 by i+=1 {
			ent_ext.entity_detection("The Humboldt University of Berlin is situated in Berlin, Germany", ["LOC", "ORG"]);
		}
	}
}