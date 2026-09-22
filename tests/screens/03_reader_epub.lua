local books = os.getenv("RITDER_EMU_BOOKS")
return {
    { "open", books .. "/Truyen ngan.epub", 4 },
    { "shot", "01_page" },
    { "key", "RIGHT", 1.5 },
    { "shot", "02_next_page" },
    { "key", "START", 1 },
    { "shot", "03_reader_menu" },
    { "keys", "DOWN DOWN DOWN" },
    { "shot", "04_reader_menu_focus" },
    { "key", "B" },
    { "key", "DOWN", 1 },
    { "shot", "05_text_cursor" },
}
