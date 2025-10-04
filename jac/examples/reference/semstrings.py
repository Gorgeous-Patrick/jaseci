from __future__ import annotations
from jaclang.runtimelib.builtin import *
from jaclang import JacMachineInterface as _jl
import byllm
from byllm import Model
llm = Model(model_name='mockllm', outputs=['R8@jL3pQ'])

@_jl.sem('Generates and returns password that:\n- contain at least 8 characters\n- contain at least one uppercase letter\n- contain at least one lowercase letter\n- contain at least one digit\n- contain at least one special character\n', {})
def generate_password() -> str:
    return _jl.call_llm(model=llm(), mtir=byllm.MTIR.factory(caller=generate_password, args={}, call_params=llm().call_params))
password = generate_password()
print('Generated password:', password)
