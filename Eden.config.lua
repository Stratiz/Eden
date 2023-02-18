-- Config file for Eden framework (https://github.com/Stratiz/Eden)
return {
    DEBUG_LEVEL = 1,
    -- 1 = Errors & Warnings only, 2 = Phase info, 3 = Module timings

    DEBUG_IN_GAME = false,
    -- If true, will print debug messages to the in-game console. Warnings and errors will always be printed to the in-game console.

    FIND_TIMEOUT = 3,
    -- How long to wait for a module to be found

    LONG_LOAD_TIMEOUT = 5,
    -- How long to wait for a module to load

    LONG_INIT_TIMEOUT = 8,
    -- How long to wait for a module to initialize

    PATH_SEPERATOR = "/",
    -- The seperator used in paths ("Shared/Dir/Example")

    STATIC_DIRECTORY_KEYWORD = "static",
    -- The keyword used to indicate a static directory ("Shared/static/Example")
}