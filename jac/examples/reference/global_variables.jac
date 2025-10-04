# Global variables - Module-level variable declarations

# Let with private access tag
let:priv a = 5;

# Global with public access tag
glob:pub X = 10;

# Global with protected access tag
glob:protect y = 15;

# Global without access tag
glob z = 20;

# Private object declaration
obj:priv Myobj{}

with entry:__main__ {
    print(a, X, y, z);
}
