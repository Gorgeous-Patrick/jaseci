import from jaclang.runtimelib.machine {JacMachine}

node Basic{}

walker BasicWalker {
  can basic with Basic entry {
    print("hello");
    visit [-->];
  }
}

with entry {
  a = Basic();
  b = Basic();
  c = Basic();
  root ++> a;
  a ++> c;
  root ++> b;
  c ++> b;
  wlk1 = a spawn BasicWalker();
  JacMachine.mapping(wlk1, a);
  # Run on DPU
}
