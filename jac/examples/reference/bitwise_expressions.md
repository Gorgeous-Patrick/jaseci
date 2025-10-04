Bitwise expressions perform operations on the binary representations of integers, manipulating individual bits using logical operations and shift operators.

**Bitwise AND (&)**

Line 7 demonstrates the bitwise AND operator: `5 & 3`. This performs a logical AND on each bit position:
- 5 in binary: 101
- 3 in binary: 011
- Result: 001 (decimal 1)

Each bit in the result is 1 only if both corresponding bits in the operands are 1.

**Bitwise OR (|)**

Line 10 shows the bitwise OR operator: `5 | 3`. This performs a logical OR on each bit position:
- 5 in binary: 101
- 3 in binary: 011
- Result: 111 (decimal 7)

Each bit in the result is 1 if either corresponding bit in the operands is 1.

**Bitwise XOR (^)**

Line 13 demonstrates the bitwise XOR (exclusive OR) operator: `5 ^ 3`:
- 5 in binary: 101
- 3 in binary: 011
- Result: 110 (decimal 6)

Each bit in the result is 1 only if the corresponding bits in the operands are different.

**Bitwise NOT (~)**

Line 16 shows the bitwise NOT operator: `~5`. This inverts all bits in the binary representation:
- 5 in binary: 101
- Result: -6 (due to two's complement representation)

In two's complement arithmetic, `~x` equals `-(x + 1)`.

**Left Shift (<<)**

Line 19 demonstrates left shift: `5 << 1`. This shifts all bits one position to the left, filling with zeros:
- 5 in binary: 101
- After shift: 1010 (decimal 10)

Left shifting by n positions is equivalent to multiplying by 2^n.

**Right Shift (>>)**

Line 22 shows right shift: `5 >> 1`. This shifts all bits one position to the right:
- 5 in binary: 101
- After shift: 10 (decimal 2)

Right shifting by n positions is equivalent to integer division by 2^n.

**Operator Precedence**

Lines 25-26 show that bitwise operations can be combined with parentheses to control precedence: `(8 | 4) & 12`. The OR operation executes first due to parentheses, then AND is applied to the result.

**Bitwise Operations with Variables**

Lines 29-33 demonstrate using bitwise operators with variables:
- `a = 15` (binary: 1111)
- `b = 7` (binary: 0111)
- `a & b = 7` (binary: 0111)
- `a | b = 15` (binary: 1111)
- `a ^ b = 8` (binary: 1000)

Bitwise operations are commonly used for flag manipulation, optimization, cryptography, and low-level data processing.