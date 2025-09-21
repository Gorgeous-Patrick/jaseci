import from jaclang.runtimelib.machine {JacMachine}

node Basic{
  has name: int;
  def get_type_def() {
    return "";
  }
  def get_byte_stream() {
    return b"";
  }
}

walker BasicWalker {
  has num: int = 10;
  can basic with Basic entry {
    print("hello");
    JacMachine.par_visit(self, [-->]);
    # for i in [-->] {
    #   task = flow spawn BasicWalker() on i;
    # }
  }
  def get_type_def() {
    return "";
  }
  def get_byte_stream() {
    return b"";
  }
}

with entry {
  a = Basic(name = 1);
  b = Basic(name = 2);
  c = Basic(name = 3);
  root ++> a;
  a ++> c;
  a ++> b;
  wlk1 = a spawn BasicWalker();
  # JacMachine.wait_par_walkers();
  # wlk2 = b spawn BasciWalker();
  # Run on DPU
}
