"""Generated FX forward for inspection; tensors are bound by Executable."""
import torch
from math import inf

def forward(self, input_0, input_1):
    tensor_2 = self.tensor_2
    tensor_3 = self.tensor_3
    matmul = torch.matmul(input_1, tensor_2);  input_1 = tensor_2 = None
    gt = torch.gt(input_0, tensor_3);  tensor_3 = None
    cond_true = self.cond_true
    cond_false = self.cond_false
    cond = torch.ops.higher_order.cond(gt, cond_true, cond_false, (input_0, matmul));  gt = cond_true = cond_false = input_0 = matmul = None
    getitem = cond[0];  cond = None
    return (getitem, ())

# Extracted branch module: cond_true
def forward(self, operand_0, operand_1):
    add = torch.add(operand_1, operand_0);  operand_1 = operand_0 = None
    contiguous = add.contiguous();  add = None
    clone = contiguous.clone();  contiguous = None
    return (clone,)

# Extracted branch module: cond_false
def forward(self, operand_0, operand_1):
    sub = torch.sub(operand_1, operand_0);  operand_1 = operand_0 = None
    contiguous = sub.contiguous();  sub = None
    clone = contiguous.clone();  contiguous = None
    return (clone,)
