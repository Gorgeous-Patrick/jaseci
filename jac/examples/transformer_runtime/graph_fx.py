"""Generated FX forward for inspection; tensors are bound by Executable."""
import torch
from math import inf

def forward(self, input_0, input_1):
    tensor_2 = self.tensor_2
    tensor_3 = self.tensor_3
    tensor_4 = self.tensor_4
    tensor_5 = self.tensor_5
    tensor_6 = self.tensor_6
    tensor_7 = self.tensor_7
    tensor_8 = self.tensor_8
    tensor_9 = self.tensor_9
    tensor_10 = self.tensor_10
    tensor_11 = self.tensor_11
    tensor_12 = self.tensor_12
    tensor_13 = self.tensor_13
    tensor_14 = self.tensor_14
    tensor_15 = self.tensor_15
    tensor_16 = self.tensor_16
    tensor_17 = self.tensor_17
    tensor_18 = self.tensor_18
    tensor_19 = self.tensor_19
    tensor_20 = self.tensor_20
    tensor_21 = self.tensor_21
    tensor_22 = self.tensor_22
    tensor_23 = self.tensor_23
    tensor_24 = self.tensor_24
    tensor_25 = self.tensor_25
    tensor_26 = self.tensor_26
    tensor_27 = self.tensor_27
    tensor_28 = self.tensor_28
    tensor_29 = self.tensor_29
    tensor_30 = self.tensor_30
    tensor_31 = self.tensor_31
    tensor_32 = self.tensor_32
    tensor_33 = self.tensor_33
    tensor_34 = self.tensor_34
    tensor_35 = self.tensor_35
    tensor_36 = self.tensor_36
    tensor_37 = self.tensor_37
    tensor_38 = self.tensor_38
    tensor_39 = self.tensor_39
    tensor_40 = self.tensor_40
    tensor_41 = self.tensor_41
    tensor_42 = self.tensor_42
    tensor_43 = self.tensor_43
    tensor_44 = self.tensor_44
    tensor_45 = self.tensor_45
    tensor_46 = self.tensor_46
    tensor_47 = self.tensor_47
    tensor_48 = self.tensor_48
    tensor_49 = self.tensor_49
    tensor_50 = self.tensor_50
    tensor_51 = self.tensor_51
    tensor_52 = self.tensor_52
    tensor_53 = self.tensor_53
    tensor_54 = self.tensor_54
    tensor_55 = self.tensor_55
    tensor_56 = self.tensor_56
    tensor_57 = self.tensor_57
    getattr_1 = input_0.shape
    getattr_2 = input_0.device
    getitem = getattr_1[0];  getattr_1 = None
    arange = torch.arange(getitem, dtype = torch.int64, device = getattr_2);  getitem = getattr_2 = None
    getattr_3 = input_1.shape
    getattr_4 = input_1.device
    getitem_1 = getattr_3[0];  getattr_3 = None
    arange_1 = torch.arange(getitem_1, dtype = torch.int64, device = getattr_4);  getitem_1 = getattr_4 = None
    getattr_5 = input_1.shape
    getattr_6 = input_1.device
    getitem_2 = getattr_5[0]
    getitem_3 = getattr_5[0];  getattr_5 = None
    full = torch.full((getitem_2, getitem_3), 1, dtype = torch.bool, device = getattr_6);  getitem_2 = getitem_3 = getattr_6 = None
    index_select = torch.index_select(tensor_4, 0, input_0);  tensor_4 = input_0 = None
    index_select_1 = torch.index_select(tensor_5, 0, input_1);  tensor_5 = input_1 = None
    index_select_2 = torch.index_select(tensor_3, 0, arange);  arange = None
    index_select_3 = torch.index_select(tensor_3, 0, arange_1);  tensor_3 = arange_1 = None
    triu = full.triu(1);  full = None
    mul = torch.mul(index_select, tensor_2);  index_select = None
    mul_1 = torch.mul(index_select_1, tensor_2);  index_select_1 = tensor_2 = None
    add = torch.add(mul, index_select_2);  mul = index_select_2 = None
    add_1 = torch.add(mul_1, index_select_3);  mul_1 = index_select_3 = None
    matmul = torch.matmul(add, tensor_6);  tensor_6 = None
    matmul_1 = torch.matmul(add, tensor_8);  tensor_8 = None
    matmul_2 = torch.matmul(add, tensor_10);  tensor_10 = None
    matmul_3 = torch.matmul(add_1, tensor_25);  tensor_25 = None
    matmul_4 = torch.matmul(add_1, tensor_27);  tensor_27 = None
    matmul_5 = torch.matmul(add_1, tensor_29);  tensor_29 = None
    add_2 = torch.add(matmul, tensor_7);  matmul = tensor_7 = None
    add_3 = torch.add(matmul_1, tensor_9);  matmul_1 = tensor_9 = None
    add_4 = torch.add(matmul_2, tensor_11);  matmul_2 = tensor_11 = None
    add_5 = torch.add(matmul_3, tensor_26);  matmul_3 = tensor_26 = None
    add_6 = torch.add(matmul_4, tensor_28);  matmul_4 = tensor_28 = None
    add_7 = torch.add(matmul_5, tensor_30);  matmul_5 = tensor_30 = None
    reshape = add_2.reshape((-1, 2, 4));  add_2 = None
    reshape_1 = add_3.reshape((-1, 2, 4));  add_3 = None
    reshape_2 = add_4.reshape((-1, 2, 4));  add_4 = None
    reshape_3 = add_5.reshape((-1, 2, 4));  add_5 = None
    reshape_4 = add_6.reshape((-1, 2, 4));  add_6 = None
    reshape_5 = add_7.reshape((-1, 2, 4));  add_7 = None
    transpose = reshape.transpose(0, 1);  reshape = None
    transpose_1 = reshape_1.transpose(0, 1);  reshape_1 = None
    transpose_2 = reshape_2.transpose(0, 1);  reshape_2 = None
    transpose_3 = reshape_3.transpose(0, 1);  reshape_3 = None
    transpose_4 = reshape_4.transpose(0, 1);  reshape_4 = None
    transpose_5 = reshape_5.transpose(0, 1);  reshape_5 = None
    transpose_6 = transpose_1.transpose(-2, -1);  transpose_1 = None
    transpose_7 = transpose_4.transpose(-2, -1);  transpose_4 = None
    matmul_6 = torch.matmul(transpose, transpose_6);  transpose = transpose_6 = None
    matmul_7 = torch.matmul(transpose_3, transpose_7);  transpose_3 = transpose_7 = None
    mul_2 = torch.mul(matmul_6, tensor_12);  matmul_6 = tensor_12 = None
    mul_3 = torch.mul(matmul_7, tensor_31);  matmul_7 = tensor_31 = None
    softmax = torch.softmax(mul_2, dim = -1);  mul_2 = None
    masked_fill = mul_3.masked_fill(triu, -inf);  mul_3 = triu = None
    matmul_8 = torch.matmul(softmax, transpose_2);  softmax = transpose_2 = None
    softmax_1 = torch.softmax(masked_fill, dim = -1);  masked_fill = None
    transpose_8 = matmul_8.transpose(0, 1);  matmul_8 = None
    matmul_9 = torch.matmul(softmax_1, transpose_5);  transpose_5 = None
    contiguous = transpose_8.contiguous();  transpose_8 = None
    transpose_9 = matmul_9.transpose(0, 1);  matmul_9 = None
    reshape_6 = contiguous.reshape((-1, 8));  contiguous = None
    contiguous_1 = transpose_9.contiguous();  transpose_9 = None
    matmul_10 = torch.matmul(reshape_6, tensor_13);  reshape_6 = tensor_13 = None
    reshape_7 = contiguous_1.reshape((-1, 8));  contiguous_1 = None
    add_8 = torch.add(matmul_10, tensor_14);  matmul_10 = tensor_14 = None
    matmul_11 = torch.matmul(reshape_7, tensor_32);  reshape_7 = tensor_32 = None
    add_9 = torch.add(add_8, add);  add_8 = add = None
    add_10 = torch.add(matmul_11, tensor_33);  matmul_11 = tensor_33 = None
    mean = add_9.mean(dim = -1, keepdim = True)
    add_11 = torch.add(add_10, add_1);  add_10 = add_1 = None
    sub = torch.sub(add_9, mean);  add_9 = mean = None
    mean_1 = add_11.mean(dim = -1, keepdim = True)
    square = torch.square(sub)
    sub_1 = torch.sub(add_11, mean_1);  add_11 = mean_1 = None
    mean_2 = square.mean(dim = -1, keepdim = True);  square = None
    square_1 = torch.square(sub_1)
    add_12 = torch.add(mean_2, tensor_15);  mean_2 = tensor_15 = None
    mean_3 = square_1.mean(dim = -1, keepdim = True);  square_1 = None
    rsqrt = torch.rsqrt(add_12);  add_12 = None
    add_13 = torch.add(mean_3, tensor_34);  mean_3 = tensor_34 = None
    mul_4 = torch.mul(sub, rsqrt);  sub = rsqrt = None
    rsqrt_1 = torch.rsqrt(add_13);  add_13 = None
    mul_5 = torch.mul(mul_4, tensor_16);  mul_4 = tensor_16 = None
    mul_6 = torch.mul(sub_1, rsqrt_1);  sub_1 = rsqrt_1 = None
    add_14 = torch.add(mul_5, tensor_17);  mul_5 = tensor_17 = None
    mul_7 = torch.mul(mul_6, tensor_35);  mul_6 = tensor_35 = None
    matmul_12 = torch.matmul(add_14, tensor_18);  tensor_18 = None
    add_15 = torch.add(mul_7, tensor_36);  mul_7 = tensor_36 = None
    add_16 = torch.add(matmul_12, tensor_19);  matmul_12 = tensor_19 = None
    matmul_13 = torch.matmul(add_15, tensor_37);  tensor_37 = None
    relu = torch.relu(add_16);  add_16 = None
    add_17 = torch.add(matmul_13, tensor_38);  matmul_13 = tensor_38 = None
    matmul_14 = torch.matmul(relu, tensor_20);  relu = tensor_20 = None
    reshape_8 = add_17.reshape((-1, 2, 4));  add_17 = None
    add_18 = torch.add(matmul_14, tensor_21);  matmul_14 = tensor_21 = None
    transpose_10 = reshape_8.transpose(0, 1);  reshape_8 = None
    add_19 = torch.add(add_18, add_14);  add_18 = add_14 = None
    mean_4 = add_19.mean(dim = -1, keepdim = True)
    sub_2 = torch.sub(add_19, mean_4);  add_19 = mean_4 = None
    square_2 = torch.square(sub_2)
    mean_5 = square_2.mean(dim = -1, keepdim = True);  square_2 = None
    add_20 = torch.add(mean_5, tensor_22);  mean_5 = tensor_22 = None
    rsqrt_2 = torch.rsqrt(add_20);  add_20 = None
    mul_8 = torch.mul(sub_2, rsqrt_2);  sub_2 = rsqrt_2 = None
    mul_9 = torch.mul(mul_8, tensor_23);  mul_8 = tensor_23 = None
    add_21 = torch.add(mul_9, tensor_24);  mul_9 = tensor_24 = None
    matmul_15 = torch.matmul(add_21, tensor_39);  tensor_39 = None
    matmul_16 = torch.matmul(add_21, tensor_41);  tensor_41 = None
    add_22 = torch.add(matmul_15, tensor_40);  matmul_15 = tensor_40 = None
    add_23 = torch.add(matmul_16, tensor_42);  matmul_16 = tensor_42 = None
    reshape_9 = add_22.reshape((-1, 2, 4));  add_22 = None
    reshape_10 = add_23.reshape((-1, 2, 4));  add_23 = None
    transpose_11 = reshape_9.transpose(0, 1);  reshape_9 = None
    transpose_12 = reshape_10.transpose(0, 1);  reshape_10 = None
    transpose_13 = transpose_11.transpose(-2, -1);  transpose_11 = None
    matmul_17 = torch.matmul(transpose_10, transpose_13);  transpose_10 = transpose_13 = None
    mul_10 = torch.mul(matmul_17, tensor_43);  matmul_17 = tensor_43 = None
    softmax_2 = torch.softmax(mul_10, dim = -1);  mul_10 = None
    matmul_18 = torch.matmul(softmax_2, transpose_12);  softmax_2 = transpose_12 = None
    transpose_14 = matmul_18.transpose(0, 1);  matmul_18 = None
    contiguous_2 = transpose_14.contiguous();  transpose_14 = None
    reshape_11 = contiguous_2.reshape((-1, 8));  contiguous_2 = None
    matmul_19 = torch.matmul(reshape_11, tensor_44);  reshape_11 = tensor_44 = None
    add_24 = torch.add(matmul_19, tensor_45);  matmul_19 = tensor_45 = None
    add_25 = torch.add(add_24, add_15);  add_24 = add_15 = None
    mean_6 = add_25.mean(dim = -1, keepdim = True)
    sub_3 = torch.sub(add_25, mean_6);  add_25 = mean_6 = None
    square_3 = torch.square(sub_3)
    mean_7 = square_3.mean(dim = -1, keepdim = True);  square_3 = None
    add_26 = torch.add(mean_7, tensor_46);  mean_7 = tensor_46 = None
    rsqrt_3 = torch.rsqrt(add_26);  add_26 = None
    mul_11 = torch.mul(sub_3, rsqrt_3);  sub_3 = rsqrt_3 = None
    mul_12 = torch.mul(mul_11, tensor_47);  mul_11 = tensor_47 = None
    add_27 = torch.add(mul_12, tensor_48);  mul_12 = tensor_48 = None
    matmul_20 = torch.matmul(add_27, tensor_49);  tensor_49 = None
    add_28 = torch.add(matmul_20, tensor_50);  matmul_20 = tensor_50 = None
    relu_1 = torch.relu(add_28);  add_28 = None
    matmul_21 = torch.matmul(relu_1, tensor_51);  relu_1 = tensor_51 = None
    add_29 = torch.add(matmul_21, tensor_52);  matmul_21 = tensor_52 = None
    add_30 = torch.add(add_29, add_27);  add_29 = add_27 = None
    mean_8 = add_30.mean(dim = -1, keepdim = True)
    sub_4 = torch.sub(add_30, mean_8);  add_30 = mean_8 = None
    square_4 = torch.square(sub_4)
    mean_9 = square_4.mean(dim = -1, keepdim = True);  square_4 = None
    add_31 = torch.add(mean_9, tensor_53);  mean_9 = tensor_53 = None
    rsqrt_4 = torch.rsqrt(add_31);  add_31 = None
    mul_13 = torch.mul(sub_4, rsqrt_4);  sub_4 = rsqrt_4 = None
    mul_14 = torch.mul(mul_13, tensor_54);  mul_13 = tensor_54 = None
    add_32 = torch.add(mul_14, tensor_55);  mul_14 = tensor_55 = None
    matmul_22 = torch.matmul(add_32, tensor_56);  add_32 = tensor_56 = None
    add_33 = torch.add(matmul_22, tensor_57);  matmul_22 = tensor_57 = None
    softmax_3 = torch.softmax(add_33, dim = -1);  add_33 = None
    return (softmax_3, (softmax_1, add_21))
