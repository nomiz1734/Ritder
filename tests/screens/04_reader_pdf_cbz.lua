local books = os.getenv("RITDER_EMU_BOOKS")
return {
    { "open", books .. "/Sach mau.pdf", 4 },
    { "shot", "01_pdf_page" },
    { "key", "R1", 1.5 },
    { "shot", "02_pdf_next" },
    { "key", "Y", 2 },
    { "open", books .. "/Truyen tranh/Truyen mau.cbz", 4 },
    { "shot", "03_cbz_page" },
    { "key", "R2", 1.5 },
    { "shot", "04_cbz_next" },
}
