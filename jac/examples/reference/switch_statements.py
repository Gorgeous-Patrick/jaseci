from __future__ import annotations

def switch_case(Num: int) -> None:
    match Num:
        case 2 | 3 | 10:
            print('Matched case for value: 2, 3, 10')
        case 15 | 20:
            print('Matched case for value: 15, 20')
        case _:
            print('No match found for value: ' + str(Num))
switch_case(3)
switch_case(15)
switch_case(25)
