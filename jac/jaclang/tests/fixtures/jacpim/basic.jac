import from jaclang.runtimelib.machine {JacMachine}

node Basic{
  def get_type_def() {
    return "";
  }
  def get_byte_stream() {
    return b"";
  }
}

walker BasicWalker {
  can basic with Basic entry {
    print("hello");
    visit [-->];
  }
  def get_type_def() {
    return "";
  }
  def get_byte_stream() {
    return b"";
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
  # wlk2 = b spawn BasciWalker();
  # Run on DPU
}
