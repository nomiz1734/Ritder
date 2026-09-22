-- Main menu (START) in the file browser: focus highlight, LEFT/RIGHT between tabs, submenus.
return {
    { "key", "START", 1 },
    { "shot", "01_menu_open" },
    { "keys", "DOWN" },
    { "shot", "02_menu_focus" },
    { "key", "RIGHT", 1 },
    { "shot", "03_tab_settings" },
    { "keys", "DOWN DOWN A", 1 },
    { "shot", "04_submenu" },
    { "key", "LEFT", 1 },
    { "shot", "05_back_from_submenu" },
    { "keys", "RIGHT RIGHT RIGHT", 1 },
    { "shot", "06_tab_main" },
    { "keys", "DOWN DOWN DOWN DOWN DOWN DOWN" },
    { "shot", "07_main_tab_focus" },
    { "keys", "UP A", 1 },
    { "shot", "08_help_submenu" },
}
