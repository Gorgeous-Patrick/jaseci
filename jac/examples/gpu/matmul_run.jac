"""Run Jac matrix multiplication on CUDA and compare with a serial reference."""

import math;
import from matmul_api { gpu_matmul, serial_matmul }

with entry {
    a = [[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]];
    b = [[7.0, 8.0], [9.0, 10.0], [11.0, 12.0]];
    small = gpu_matmul(a, b);
    assert small.execution.gpu_executed;
    assert small.values == [[58.0, 64.0], [139.0, 154.0]];
    print("A @ B:", small.values);

    # Rectangular dimensions and 1056 output lanes cross warp/block boundaries.
    rows = 32; inner = 16; columns = 33;
    a = [[float((row * 7 + k * 3) % 19 - 9) / 7.0
        for k in range(inner)] for row in range(rows)];
    b = [[float((k * 5 + col * 11) % 23 - 11) / 9.0
        for col in range(columns)] for k in range(inner)];
    expected = serial_matmul(a, b);
    result = gpu_matmul(a, b);
    assert result.execution.gpu_executed;
    for row in range(rows) {
        for col in range(columns) {
            assert math.isclose(result.values[row][col], expected[row][col],
                rel_tol=1e-12, abs_tol=1e-12);
        }
    }
    print("GPU:", result.execution.gpu_name);
    print(f"PASS: {rows}x{inner} @ {inner}x{columns}, {rows * columns} output walkers");
    print("Device payload bytes:", result.execution.memory.payload_bytes());
}
