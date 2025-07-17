edge SumEdge {}
node Data {
  has data: int;
}

node FinalResult {
  has result: list[int] = [0] * 100;
}

walker histogram {
  has tmp_result: list[int] = [0] * 100;
  can get with Data entry {
    self.tmp_result[here.data % 100] += 1;
    visit [->:SumEdge:->];
  }

  can sum_up with FinalResult entry {
    for i in range(100) {
      here.result[i] += self.tmp_result[i];
    }
  }
}

with entry {
  THREAD_NUM = 10;
  DATA_LEN = 40;
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
  final = FinalResult(result = [0] * 100);
  for tail in tails {
    tail +>:SumEdge:+> final;
  }

  walkers = [];
  wlk1 = heads[0] spawn histogram();
  print(final.result);
}

# Single number per node
# Figure out the Prim Number / DPU.
