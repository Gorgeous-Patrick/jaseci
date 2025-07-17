node Data {
    has id: str;
    has data: int = 0;
}

node Result {
    has id: str;
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
    vectorA = [1, 2, 3, 4, 5];
    vectorB = [6, 7, 8, 9, 10];
    vectorAData = [Data(id=f"A{idx}", data = num) for (idx, num) in enumerate(vectorA)];
    vectorBData = [Data(id=f"B{idx}", data = num) for (idx, num) in enumerate(vectorB)];
    vectorCData = [Result(id=f"C{idx}") for (idx, num) in enumerate(vectorB)];
    for i in range(len(vectorAData)) {
        root ++> vectorAData[i];
        vectorAData[i] ++> vectorBData[i];
        vectorBData[i] ++> vectorCData[i];
    }
    wlk1 = vectorAData[0] spawn va();
}
