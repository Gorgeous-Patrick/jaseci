"""Pytorch Fix Pass."""

import ast as ast3
from typing import Optional, TypeVar, cast

import jaclang.compiler.unitree as uni
from jaclang.compiler.constant import Tokens as Tok
from jaclang.compiler.passes import UniPass


T = TypeVar("T", bound=ast3.AST)


class PreDynamoPass(UniPass):
    """Pre-Dynamo pass for PyTorch."""

    def enter_node(self, node: uni.UniNode) -> None:
        """Enter node."""
        super().enter_node(node)

    def exit_node(self, node: uni.UniNode) -> None:
        """Exit node."""
        super().exit_node(node)

    def replace_node(self, new_node: uni.UniNode, old_node: uni.UniNode) -> None:
        """Copy location from old node to new node."""
        pass

    def gen_name(self, node: uni.UniNode, name: Tok, value: str) -> uni.Name:
        """Generate Name."""
        return uni.Name(
            name=name,
            value=value,
            orig_src=node.loc.orig_src,
            col_start=node.loc.col_start,
            col_end=0,
            line=node.loc.first_line,
            end_line=node.loc.last_line,
            pos_start=0,
            pos_end=0,
        )

    def check_same_lhs(
        self, assign_a: uni.UniNode, assign_b: uni.UniNode
    ) -> Optional[uni.Name]:
        """Return the common LHS target if both are simple assignment with same target."""
        if not (
            isinstance(assign_a, uni.Assignment)
            and isinstance(assign_b, uni.Assignment)
        ):
            return None
        ta, tb = assign_a.target[0], assign_b.target[0]
        if not (isinstance(ta, uni.Name) and isinstance(tb, uni.Name)):
            return None
        if ta.value != tb.value:
            return None
        return ta  # common target

    def exit_if_stmt(self, node: uni.IfStmt) -> None:
        """Exit if statement."""
        a0 = node.body[0]
        new_node = None
        if node.else_body:
            b0 = node.else_body.body[0]
        else:
            return
        if isinstance(a0, uni.Assignment) and isinstance(b0, uni.Assignment):
            lhs = self.check_same_lhs(a0, b0)
            if lhs:
                func_name = self.gen_name(node, Tok.NAME, "torch")
                attr_name = self.gen_name(node, Tok.NAME, "where")
                target = uni.AtomTrailer(
                    target=func_name,
                    right=attr_name,
                    is_attr=True,
                    is_null_ok=False,
                    kid=[func_name, attr_name],
                )
                call = uni.FuncCall(
                    target=target,
                    params=[
                        node.condition,
                        cast(uni.Expr, a0.value),
                        cast(uni.Expr, b0.value),
                    ],
                    genai_call=None,
                    kid=[target, node.condition, a0, b0],
                )
                new_node = uni.Assignment(
                    target=[lhs], value=call, type_tag=None, kid=[lhs, call]
                )

        elif isinstance(a0, uni.ReturnStmt) and isinstance(b0, uni.ReturnStmt):
            aexpr, bexpr = a0.expr, b0.expr
            if aexpr is None or bexpr is None:
                return
            func_name = self.gen_name(node, Tok.NAME, "torch")
            attr_name = self.gen_name(node, Tok.NAME, "where")
            target = uni.AtomTrailer(
                target=func_name,
                right=attr_name,
                is_attr=True,
                is_null_ok=False,
                kid=[func_name, attr_name],
            )
            call = uni.FuncCall(
                target=target,
                params=[node.condition, cast(uni.Expr, aexpr), cast(uni.Expr, bexpr)],
                genai_call=None,
                kid=[target, node.condition, a0, b0],
            )
            new_node = uni.ReturnStmt(expr=call, kid=[call])
        if new_node is not None:
            new_node.parent = node.parent
            if (
                (parent := node.parent)
                and hasattr(parent, "body")
                and node in parent.body
            ):
                parent.body[parent.body.index(node)] = new_node
                parent.kid[parent.kid.index(node)] = new_node
