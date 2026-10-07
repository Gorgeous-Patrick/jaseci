"""Generated FX forward for inspection; tensors are bound by Executable."""
import torch
from math import inf

def forward(self, input_0, input_1):
    tensor_2 = self.tensor_2
    tensor_3 = self.tensor_3
    tensor_4 = self.tensor_4
    gt = torch.gt(input_0, tensor_2);  input_0 = tensor_2 = None
    cond_true = self.cond_true
    cond_false = self.cond_false
    cond = torch.ops.higher_order.cond(gt, cond_true, cond_false, (input_1, tensor_3, tensor_4));  gt = cond_true = cond_false = input_1 = tensor_3 = tensor_4 = None
    getitem = cond[0];  cond = None
    return (getitem, ())

# Extracted branch module: cond_true
def forward(self, operand_0, operand_1, operand_2):
    matmul = torch.matmul(operand_0, operand_1);  operand_0 = operand_1 = None
    contiguous = matmul.contiguous();  matmul = None
    clone = contiguous.clone();  contiguous = None
    return (clone,)

# Extracted branch module: cond_false
def forward(self, operand_0, operand_1, operand_2):
    matmul = torch.matmul(operand_0, operand_2);  operand_0 = operand_2 = None
    contiguous = matmul.contiguous();  matmul = None
    clone = contiguous.clone();  contiguous = None
    return (clone,)
