"""Generated FX forward for inspection; tensors are bound by Executable."""
import torch
from math import inf

def forward(self, input_0, input_1):
    tensor_2 = self.tensor_2
    tensor_3 = self.tensor_3
    square = torch.square(input_0)
    matmul = torch.matmul(input_1, tensor_2);  input_1 = tensor_2 = None
    add = torch.add(square, input_0);  square = input_0 = None
    gt = torch.gt(add, tensor_3)
    cond_true = self.cond_true
    cond_false = self.cond_false
    cond = torch.ops.higher_order.cond(gt, cond_true, cond_false, (matmul, add));  gt = cond_true = cond_false = matmul = add = None
    getitem = cond[0];  cond = None
    add_1 = torch.add(getitem, tensor_3);  getitem = tensor_3 = None
    return (add_1, ())

# Extracted branch module: cond_true
def forward(self, operand_0, operand_1):
    add = torch.add(operand_0, operand_1);  operand_0 = operand_1 = None
    contiguous = add.contiguous();  add = None
    clone = contiguous.clone();  contiguous = None
    return (clone,)

# Extracted branch module: cond_false
def forward(self, operand_0, operand_1):
    square = torch.square(operand_0);  operand_0 = None
    sub = torch.sub(square, operand_1);  square = operand_1 = None
    contiguous = sub.contiguous();  sub = None
    clone = contiguous.clone();  contiguous = None
    return (clone,)
