import from jaclang.runtimelib.machine {JacMachine}

node Basic{}

walker BasciWalker {
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
  wlk1 = a spawn BasciWalker();
  # wlk2 = b spawn BasciWalker();
  # Run on DPU
}
