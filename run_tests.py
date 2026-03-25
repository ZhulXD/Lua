#!/usr/bin/env python3
import ctypes
import os
import sys
import platform

def find_lua_lib():
    # Attempt to find the Lua shared library on various systems
    system = platform.system()
    if system == "Linux":
        paths = [
            "/usr/lib/x86_64-linux-gnu/liblua5.4.so.0",
            "/usr/lib/liblua5.4.so.0",
            "/usr/local/lib/liblua5.4.so.0",
            "/usr/lib/x86_64-linux-gnu/liblua5.4.so",
            "/usr/lib/liblua5.4.so",
        ]
    elif system == "Darwin": # macOS
        paths = [
            "/usr/local/lib/liblua.5.4.dylib",
            "/opt/homebrew/lib/liblua.5.4.dylib",
        ]
    elif system == "Windows":
        paths = ["lua54.dll"]
    else:
        paths = []

    for path in paths:
        if os.path.exists(path) or system == "Windows":
            try:
                return ctypes.CDLL(path)
            except:
                continue
    return None

def run_lua_test(filename):
    lua_lib = find_lua_lib()
    if not lua_lib:
        print("Warning: Lua 5.4 shared library not found. Falling back to shell command 'lua' or 'lua5.4' if available.")
        # Fallback to shell execution if ctypes fails
        for cmd in ["lua", "lua5.4", "lua5.1"]:
            if os.system(f"{cmd} -v > /dev/null 2>&1") == 0:
                print(f"Executing {filename} via {cmd}...")
                return os.system(f"{cmd} {filename}") == 0
        print("Error: No Lua interpreter found. Please install Lua 5.4 to run tests.")
        return False

    # Define return types and argument types for some functions
    lua_lib.luaL_newstate.restype = ctypes.c_void_p
    lua_lib.luaL_openlibs.argtypes = [ctypes.c_void_p]
    lua_lib.luaL_loadfilex.restype = ctypes.c_int
    lua_lib.luaL_loadfilex.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p]
    lua_lib.lua_pcallk.restype = ctypes.c_int
    lua_lib.lua_pcallk.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_void_p]
    lua_lib.lua_gettop.restype = ctypes.c_int
    lua_lib.lua_gettop.argtypes = [ctypes.c_void_p]
    lua_lib.lua_tolstring.restype = ctypes.c_char_p
    lua_lib.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]

    def lua_pcall(L, nargs, nresults, errfunc):
        return lua_lib.lua_pcallk(L, nargs, nresults, errfunc, 0, None)

    # Create a new Lua state
    L = lua_lib.luaL_newstate()
    if not L:
        print("Failed to create Lua state")
        return False

    lua_lib.luaL_openlibs(L)

    # Load the test file
    print(f"Executing {filename} via python ctypes bridge...")
    if lua_lib.luaL_loadfilex(L, filename.encode('utf-8'), None) == 0:
        if lua_pcall(L, 0, 0, 0) != 0:
            error_msg = lua_lib.lua_tolstring(L, -1, None).decode('utf-8')
            print(f"Error running Lua script: {error_msg}")
            return False
        else:
            return True
    else:
        error_msg = lua_lib.lua_tolstring(L, -1, None).decode('utf-8')
        print(f"Error loading Lua script: {error_msg}")
        return False

if __name__ == "__main__":
    test_file = "DrawGuess_Utility.test.lua"
    if not os.path.exists(test_file):
        print(f"Error: Test file {test_file} not found.")
        sys.exit(1)

    success = run_lua_test(test_file)
    if not success:
        sys.exit(1)
    sys.exit(0)
