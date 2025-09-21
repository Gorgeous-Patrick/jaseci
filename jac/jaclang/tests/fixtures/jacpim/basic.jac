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
    if (self.num > 0) {
      self.num = self.num - 1;

    visit [-->];
    } else {
      return;
    }
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
  # wlk2 = b spawn BasciWalker();
  # Run on DPU
}
