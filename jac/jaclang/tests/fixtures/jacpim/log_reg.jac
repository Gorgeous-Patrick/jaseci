import:py math;
node Data {
  # input: int[DIM];
  # truth: int;
  has input: list[int];
  has truth: int;
}

node Acc {
  # new_weight: int[DIM];
  has new_weight: list[int];
}

can sigmoid(x: int){
  return 1 / (1 + math.exp(-x));
}


walker log_reg_train {
  has weight: list[int];
  has grads: list[int] = [];
  can grad_calc with Data entry {
     dot = 0;
    #  DIM = len(self.weight);
     DIM = len(here.input);
     for i in range(DIM) {
      dot += self.weight[i] * here.input[i];
     }
     error = sigmoid(dot) - here.truth;
     self.grads = [0] * DIM;
     for i in range(DIM) {
      self.grads[i] = error * here.input[i];
     }
     visit [-->];
  }

  can accumulate with Acc entry {
     for i in range(len(self.grads)) {
      here.new_weight[i] += self.grads[i];
     }
  }
}

with entry {
  data1 = Data(input=[1, 2, 3], truth=1);
  data2 = Data(input=[4, 5, 6], truth=0);
  data3 = Data(input=[7, 8, 9], truth=1);
  data4 = Data(input=[10, 11, 12], truth=0);
  
  acc = Acc(new_weight=[0] * 3);
  
  data1 ++> acc;
  data2 ++> acc;
  data3 ++> acc;
  data4 ++> acc;
  
  wlk1 = data1 spawn log_reg_train(weight=[0] * 3);
  wlk2 = data2 spawn log_reg_train(weight=[0] * 3);
  wlk3 = data3 spawn log_reg_train(weight=[0] * 3);
  wlk4 = data4 spawn log_reg_train(weight=[0] * 3);

  
  print(acc.new_weight);
}
