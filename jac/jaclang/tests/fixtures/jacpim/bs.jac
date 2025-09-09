import from jaclang.runtimelib.machine {JacMachine}
import struct;
edge Left {}
edge Right {}

node BranchNode {
  has mid: int;
  def get_type_def() {
    return "uint64_t mid;";
  }

  def get_byte_stream() {
    return struct.pack("<Q", self.mid);
  }
}

node DataNode {
  has value: int;
  has index: int;
  def get_type_def() {
    return "uint64_t value; uint64_t index;";
  }
  def get_byte_stream() {
    return struct.pack("<2Q", self.value, self.index);
  }
}

walker bs {
  has value: int;
  can rundown with BranchNode entry {
    print(here.mid);
    if (self.value < here.mid) {
      visit [->:Left:->];
    } else {
      visit [->:Right:->];
    }
  }

  def get_impl_rundown_on_BranchNode() {
  return """
    printf("BranchNode ID: %u, Mid: %lu, Walker Value: %lu\\n", node_id, node->mid, walker->value);
  """;
  }

  can printnode with DataNode entry {
    print(here.value);
  }

  def get_impl_printnode_on_DataNode() {
  return """
    printf("DataNode ID: %u, Value: %lu, Index: %lu, Walker Value: %lu\\n", node_id, node->value, node->index, walker->value);
  """;
  }

  def get_type_def() {
    return "uint64_t value;";
  }

  def get_byte_stream() {
    return struct.pack("<Q", self.value);
  }
}

with entry {
  r = BranchNode(mid = 5);
  n1 = BranchNode(mid = 3);
  n2 = BranchNode(mid = 7);
  n3 = DataNode(value = 1, index = 0);
  n4 = DataNode(value = 4, index = 1);
  n5 = DataNode(value = 6, index = 2);
  n6 = DataNode(value = 8, index = 3);

  root ++> r;

  r+>:Left:+>n1;
  r+>:Right:+>n2;
  n1+>:Left:+>n3;
  n1+>:Right:+>n4;
  n2+>:Left:+>n5;
  n2+>:Right:+>n6;

  print("Starting binary search with value 5");

  wlk = r spawn bs(value = 5);
}
