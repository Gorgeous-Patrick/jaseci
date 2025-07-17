import from jaclang.runtimelib.machine {JacMachine}
node Data {
  has data: int; # Int64 in PrIM by default
}

edge SumEdge {}

node FinalResult {
  has data: int;
}

walker red {
  has result: int = 0;
  can sum_up with Data entry {
    self.result += here.data;
    visit [->:SumEdge:->];
  }
  can store with FinalResult entry {
    here.data += self.result;
    print(here.data);
  }
}

with entry {
  THREAD_NUM = 10;
  DATA_LEN = 20;
  k = 0;
  heads = [];
  tails = [];
  for i in range(THREAD_NUM - 1) {
    prev = root;
    for j in range(DATA_LEN // THREAD_NUM) {
      n = Data(data = 1);
      if (j == 0) {
        heads.append(n);
      }
      k += 1;
      prev +>:SumEdge:+> n;
      prev = n;
    }
    tails.append(prev);
  }
  prev = root;
  for i in range(DATA_LEN - k) {
    n = Data(data = 1);
    if (i == 0) {
      heads.append(n);
    }
    prev +>:SumEdge:+> n;
    prev = n;
  }
  tails.append(prev);
  final = FinalResult(data = 0);
  for tail in tails {
    tail +>:SumEdge:+> final;
  }

  walkers = [];
  for head in heads {
    walkers.append(head spawn red());
  }
}
