//! Port của frontend/ritder/brand.lua: thay "KOReader" -> "Ritder" trong chuỗi hiển thị.
//! "koreader" viết thường (đường dẫn, URL) được giữ nguyên.
pub const NAME: &str = "Ritder";
pub const REPO_URL: &str = "https://github.com/nomiz1734/Ritder";

pub fn rebrand(s: &str) -> String {
    if s.contains("KOReader") { s.replace("KOReader", NAME) } else { s.to_string() }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test] fn replaces_only_exact_case() {
        assert_eq!(rebrand("Exit KOReader now"), "Exit Ritder now");
        assert_eq!(rebrand("~/.koreader/file"), "~/.koreader/file");
    }
}
