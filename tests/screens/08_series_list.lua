-- A folder of 8 volumes (two pages of list): open one, come back, move around and page.
-- Every shot must show exactly one highlighted row.
local books = os.getenv("RITDER_EMU_BOOKS")
return {
    { "lua", function() require("apps/filemanager/filemanager").instance.file_chooser:changeToPath(books .. "/Conan") end, 1.5 },
    { "shot", "01_series" },
    { "keys", "DOWN DOWN DOWN" },
    { "shot", "02_third" },
    { "key", "A", 4 },
    { "key", "R1", 1.5 },
    { "key", "Y", 3 },
    { "shot", "03_back_from_book" },
    { "key", "UP" },
    { "shot", "04_up" },
    { "keys", "DOWN DOWN" },
    { "shot", "05_down_down" },
    { "key", "R1", 1.5 },
    { "shot", "06_next_page" },
    { "keys", "DOWN DOWN" },
    { "shot", "07_page2_down" },
    { "key", "L1", 1.5 },
    { "shot", "08_prev_page" },
    { "keys", "UP UP UP UP UP UP" },
    { "shot", "09_wrap_up" },
}
