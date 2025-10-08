"""Typed context blocks: Conditional code execution based on node/walker types."""
from __future__ import annotations
from jaclang.runtimelib.builtin import *
from jaclang import JacMachineInterface as _jl

class Product(_jl.Node):
    price: float

class Media(Product, _jl.Node):
    title: str

class Book(Media, _jl.Node):
    author: str

class Magazine(Media, _jl.Node):
    issue: int

class Electronics(Product, _jl.Node):
    name: str
    warranty_years: int

class Customer(_jl.Walker):
    name: str
    total_spent: float = 0.0

class RegularCustomer(Customer, _jl.Walker):
    loyalty_points: int = 0

class VIPCustomer(Customer, _jl.Walker):
    vip_discount: float = 0.15

class ShoppingCart(_jl.Walker):
    items_count: int = 0
    total: float = 0.0

    @_jl.on_entry
    def start(self, here: _jl.Root) -> None:
        _jl.connect(left=_jl.root(), right=Book(title='Jac Programming', author='John Doe', price=29.99))
        _jl.connect(left=_jl.root(), right=Magazine(title='Tech Today', issue=42, price=5.99))
        _jl.connect(left=_jl.root(), right=Electronics(name='Laptop', price=999.99, warranty_years=2))
        _jl.visit(self, _jl.refs(_jl.Path(here)._out().visit()))

    @_jl.on_entry
    def process_item(self, here: Product) -> None:
        print(f'[Inheritance] Processing {type(here).__name__}...')
        if isinstance(here, Book):
            print(f"  -> Book block: '{here.title}' by {here.author}")
        if isinstance(here, Magazine):
            print(f"  -> Magazine block: '{here.title}' Issue #{here.issue}")
        if isinstance(here, Electronics):
            print(f'  -> Electronics block: {here.name}, {here.warranty_years}yr warranty')
        self.items_count += 1
        self.total += here.price
        _jl.visit(self, _jl.refs(_jl.Path(here)._out().visit()))

    @_jl.on_entry
    def apply_discount(self, here: (Book, Magazine)) -> None:
        print(f'[Tuple] Applying media discount to {type(here).__name__}')
        if isinstance(here, Book):
            discount = here.price * 0.1
            print(f'  -> Book: 10% off = ${discount}')
        if isinstance(here, Magazine):
            discount = here.price * 0.2
            print(f'  -> Magazine: 20% off = ${discount}')
        _jl.visit(self, _jl.refs(_jl.Path(here)._out().visit()))

class Checkout(_jl.Node):
    transactions: int = 0

    @_jl.on_entry
    def process_payment(self, visitor: Customer) -> None:
        self.transactions += 1
        if isinstance(visitor, RegularCustomer):
            print(f'\\nRegular customer: {visitor.name}')
            print(f'Total: ${visitor.total_spent}, Points: {visitor.loyalty_points}')
        if isinstance(visitor, VIPCustomer):
            discount = visitor.total_spent * visitor.vip_discount
            final_total = visitor.total_spent - discount
            print(f'\\nVIP customer: {visitor.name}')
            print(f'Subtotal: ${visitor.total_spent}, Discount: -${discount}, Final: ${final_total}')
        if isinstance(visitor, Customer):
            print(f'Processing payment for {visitor.name}')
print('=== Demo 1: Product Inheritance Chain ===')
print('Hierarchy: Product -> Media -> Book/Magazine')
print('            Product -> Electronics\n')
cart = ShoppingCart()
_jl.spawn(_jl.root(), cart)
print(f'\\nCart: {cart.items_count} items, Total: ${cart.total}\\n')
print('=== Demo 2: Customer Inheritance Chain ===')
print('Hierarchy: Customer -> RegularCustomer/VIPCustomer\n')
checkout = _jl.connect(left=_jl.root(), right=Checkout())
base_customer = Customer(name='Charlie', total_spent=50.0)
_jl.spawn(checkout, base_customer)
regular = RegularCustomer(name='Alice', total_spent=89.97, loyalty_points=150)
_jl.spawn(checkout, regular)
vip = VIPCustomer(name='Bob', total_spent=89.97, vip_discount=0.15)
_jl.spawn(checkout, vip)
