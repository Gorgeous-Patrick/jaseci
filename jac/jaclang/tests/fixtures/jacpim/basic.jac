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
  # JacMachine.networkx_gen_png(JacMachine.get_networkx());
  wlk = a spawn BasciWalker();
  wlk = b spawn BasciWalker();
  JacMachine.mapping();

}