-- Focus moves: what gets repainted (see the EMU lines in the output), and no double highlight
-- after coming back from a book.
local books = os.getenv("RITDER_EMU_BOOKS")
return {
    { "key", "DOWN" }, { "key", "DOWN" }, { "key", "DOWN" },
    { "shot", "01_list_focus" },
    { "key", "A", 4 },
    { "key", "Y", 3 },
    { "shot", "02_back_from_book" },
    { "key", "DOWN" }, { "key", "UP" },
    { "shot", "03_moved_after_return" },
    { "key", "START", 1 },
    { "key", "DOWN" }, { "key", "DOWN" },
    { "shot", "04_menu_focus" },
    { "key", "RIGHT", 1 },
    { "key", "DOWN" },
    { "shot", "05_settings_focus" },
    { "key", "B" }, { "key", "X", 1 },
    { "key", "DOWN" }, { "key", "RIGHT" },
    { "shot", "06_dialog_button_focus" },
}
