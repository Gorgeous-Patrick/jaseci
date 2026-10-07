| device | config / dtype | walker / FX vs reference max abs | Inductor vs reference max abs |
|---|---|---:|---:|
| cpu | small_float64 | 0 | 2.6645e-15 |
| cpu | small_float32 | 2.861e-06 | 1.6689e-06 |
| cpu | medium_float64 | 0 | 1.5987e-14 |
| cpu | medium_float32 | 6.6757e-06 | 5.722e-06 |
| cuda_0 | small_float64 | 0 | 4.4409e-15 |
| cuda_0 | small_float32 | 1.1921e-06 | 1.9073e-06 |
| cuda_0 | medium_float64 | 1.2434e-14 | 1.199e-14 |
| cuda_0 | medium_float32 | 8.5831e-06 | 6.0797e-06 |
