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
    # Write C implementation for the rundown walker on BranchNode here
  return """
    if (walker->value < node->mid) {
      push_new_element_to_container(0);
    } else {
      push_new_element_to_container(1);
    }
  """;
  }

  can printnode with DataNode entry {
    print(here.value);
  }

  def get_impl_printnode_on_DataNode() {
  return """
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
  # NUM=1024;
  NUM=4;
  values = [i for i in range(NUM)];
  data_nodes = [(DataNode(value=values[i], index=i), values[i], values[i]) for i in range(NUM)];
  granularity = 1;
  # print(data_nodes);
  while (len(data_nodes) > 1) {
  new_nodes = [];
  while (len(data_nodes) > 1) {
    first = data_nodes.pop(0);
    second = data_nodes.pop(0);
    mid = second[1];
    branch = BranchNode(mid=mid);
    branch +>:Left:+>first[0];
    branch +>:Right:+>second[0];
    new_nodes.append((branch, first[1], second[2]));
  }
  data_nodes = new_nodes + data_nodes;
  # print(data_nodes);
  }
  root ++> data_nodes[0][0];
  walker_instance = data_nodes[0][0] spawn bs(value=5);
  print("Walker instance created with value 5");
}
