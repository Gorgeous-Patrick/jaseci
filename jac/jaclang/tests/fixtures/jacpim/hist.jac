node Data {
  has chunk: float;
}

node End {
  has result: list[int] = [0] * 100;
}

walker histogram {
  has tmp_result: list[int] = [0] * 100;
  can get with Data entry {
    self.tmp_result[int(here.chunk)] += 1;
    visit [-->];
  }

  can sum_up with End entry {
    for i in range(100) {
      here.result[i] += self.tmp_result[i];
    }
  }
}

with entry {
  data1 = Data(chunk=1);
  data2 = Data(chunk=3);
  data3 = Data(chunk=4);
  data4 = Data(chunk=5);
  end = End();

  data1 ++> data2;
  data2 ++> end;
  data3 ++> data4;
  data4 ++> end;
  wlk1 = data1 spawn histogram();
  wlk2 = data3 spawn histogram();
  
  print(end.result);
}

# Single number per node
# Figure out the Prim Number / DPU.
