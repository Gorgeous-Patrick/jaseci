node Data {
    has id_0: str;
    has data: int = 0;
}

node Result {
    has id_0: str;
    has data: int = 0;
}

walker va {
    has data: int = 0;
    can run with Data entry {
        self.data += here.data;
        visit [-->];
    }
    can save with Result entry {
        here.data = self.data;
        print(here.data);
    }
}


with entry {
    N = 1500;
    vectorA = list(range(N));
    vectorB = list(range(N, 2*N));
    vectorAData = [Data(id_0=f"A{idx}", data = num) for (idx, num) in enumerate(vectorA)];
    vectorBData = [Data(id_0=f"B{idx}", data = num) for (idx, num) in enumerate(vectorB)];
    vectorCData = [Result(id_0=f"C{idx}") for (idx, num) in enumerate(vectorB)];
    for i in range(len(vectorAData)) {
        root ++> vectorAData[i];
        vectorAData[i] ++> vectorBData[i];
        vectorBData[i] ++> vectorCData[i];
    }
    wlk1 = vectorAData[0] spawn va();
}
