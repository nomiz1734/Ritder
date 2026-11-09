//! Test port từ tests/lua/*.lua và tests/shell/test_install.sh của repo gốc.
//! Tên test phản ánh nguồn: <module>__<case gốc>.
use ritder_core::diagnostics;
use ritder_core::framebuffer::{bounded_rect, copy_to_screen, Buffer};
use ritder_core::input_evdev::*;
use ritder_core::install;
use ritder_core::night_pages::{self, DocKind};
use ritder_core::update;
use std::collections::BTreeMap;
use std::fs;
use std::path::PathBuf;

fn tmp(tag: &str) -> PathBuf {
    let d = std::env::temp_dir().join(format!("ritder-test-{}-{}", std::process::id(), tag));
    let _ = fs::remove_dir_all(&d);
    fs::create_dir_all(&d).unwrap();
    d
}

// ---- tests/lua/test_update.lua ----
#[test]
fn update__version_compare() {
    assert!(update::is_newer("0.1.1", "0.1.0"));
    assert!(update::is_newer("0.10.0", "0.9.9")); // numeric, not lexical
    assert!(update::is_newer("v1.0.0", "0.9"));
    assert!(update::is_newer("1.0.1", "1.0"));
    assert!(!update::is_newer("0.1.0", "0.1.0"));
    assert!(!update::is_newer("0.0.9", "0.1.0")); // never a downgrade
    assert!(!update::is_newer("1.0", "1.0.0"));
    assert_eq!(update::parse_version("v0.10.0-rc1"), vec![0, 10, 0, 1]);
}
#[test]
fn update__safe_paths() {
    assert!(update::is_safe_path("frontend/ritder/update.lua"));
    assert!(update::is_safe_path("a..b/c"));
    assert!(!update::is_safe_path("../etc/passwd"));
    assert!(!update::is_safe_path("a/../../b"));
    assert!(!update::is_safe_path("/etc/passwd"));
    assert!(!update::is_safe_path(""));
}
#[test]
fn update__protected_paths() {
    assert!(update::is_protected("userdata/settings.reader.lua"));
    assert!(update::is_protected("userdata"));
    assert!(update::is_protected("settings.json"));
    assert!(!update::is_protected("frontend/ritder/update.lua"));
}
#[test]
fn update__sha256_known_value() {
    assert_eq!(ritder_core::sha256_hex(b"abc"),
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
}
#[test]
fn update__arm64_elf_check() {
    let mut elf = vec![0u8; 64];
    elf[0..4].copy_from_slice(b"\x7fELF"); elf[4] = 2; elf[5] = 1; elf[18] = 0xB7;
    assert!(update::is_arm64_elf_bytes(&elf));
    elf[18] = 0x3E; // x86_64
    assert!(!update::is_arm64_elf_bytes(&elf));
    assert!(!update::is_arm64_elf_bytes(b"return {}"));
}
#[test]
fn update__manifest_validation_and_relative_file() {
    let sha = "ab".repeat(32);
    let body = format!("{{\"version\":\"0.2.0\",\"file\":\"ritder-update.tar.gz\",\"sha256\":\"{}\",\"size\":10}}", sha.to_uppercase());
    let m = update::validate_manifest(&body, "https://github.com/nomiz1734/Ritder/releases/latest/download/update.json").unwrap();
    assert_eq!(m.package_url, "https://github.com/nomiz1734/Ritder/releases/latest/download/ritder-update.tar.gz");
    assert_eq!(m.sha256, sha); // lowercased
    assert_eq!(m.size, Some(10));
    assert!(update::validate_manifest(&format!("{{\"file\":\"x.tar.gz\",\"sha256\":\"{sha}\"}}"), "https://example.com/update.json").is_err());
    assert!(update::validate_manifest(&format!("{{\"version\":\"1\",\"file\":\"x.tar.gz\",\"sha256\":\"abc\"}}"), "https://example.com/update.json").is_err());
    let http = format!("{{\"version\":\"1\",\"url\":\"http://example.com/x.tar.gz\",\"sha256\":\"{sha}\"}}");
    assert!(update::validate_manifest(&http, "https://example.com/update.json").unwrap_err().contains("HTTPS"));
    assert!(update::validate_manifest("not json", "https://example.com/update.json").is_err());
    assert!(update::check_https("http://example.com/update.json").is_err());
}
fn fake_arm64() -> Vec<u8> { let mut v = vec![0u8; 64]; v[0..4].copy_from_slice(b"\x7fELF"); v[4] = 2; v[5] = 1; v[18] = 0xB7; v }
fn make_tar_gz(entries: &[(&str, Vec<u8>)]) -> Vec<u8> {
    let mut tb = tar::Builder::new(Vec::new());
    for (name, data) in entries {
        let mut h = tar::Header::new_gnu(); h.set_size(data.len() as u64); h.set_mode(0o644); h.set_cksum();
        tb.append_data(&mut h, name, data.as_slice()).unwrap();
    }
    let raw = tb.into_inner().unwrap();
    let mut out = Vec::new();
    {
        let mut enc = flate2::write::GzEncoder::new(&mut out, flate2::Compression::default());
        std::io::Write::write_all(&mut enc, &raw).unwrap();
        enc.finish().unwrap();
    }
    out
}
#[test]
fn update__stage_unpacks_without_touching_app() {
    let root = tmp("stage");
    let work = root.join("userdata/update"); fs::create_dir_all(&work).unwrap();
    let pkg = root.join("pkg.tar.gz");
    fs::write(&pkg, make_tar_gz(&[
        ("luajit", fake_arm64()), ("reader.lua", b"new reader".to_vec()),
        ("launch.sh", b"l".to_vec()), ("install.sh", b"i".to_vec()),
        ("logging.sh", b"g".to_vec()), ("frontend/b.lua", b"b".to_vec()),
    ])).unwrap();
    let count = update::stage(&work, &pkg, "0.2.0").unwrap();
    assert_eq!(count, 6);
    assert_eq!(fs::read_to_string(work.join("staging/reader.lua")).unwrap(), "new reader");
    assert_eq!(update::ready_version(&work).as_deref(), Some("0.2.0"));
    assert!(!pkg.exists());
    update::discard(&work);
    assert_eq!(update::ready_version(&work), None);
    assert!(!work.join("staging").exists());
}
#[test]
fn update__stage_rejects_wrong_arch_traversal_and_missing() {
    let root = tmp("stagebad");
    let work = root.join("userdata/update"); fs::create_dir_all(&work).unwrap();
    let mut x86 = fake_arm64(); x86[18] = 0x3E;
    let pkg = root.join("pkg.tar.gz");
    fs::write(&pkg, make_tar_gz(&[("luajit", x86), ("reader.lua", b"r".to_vec()),
        ("launch.sh", b"l".to_vec()), ("install.sh", b"i".to_vec()), ("logging.sh", b"g".to_vec())])).unwrap();
    assert!(update::stage(&work, &pkg, "0.2.0").unwrap_err().contains("ARM64"));
    let pkg2 = root.join("pkg2.tar.gz");
    fs::write(&pkg2, make_tar_gz(&[("luajit", fake_arm64())])).unwrap();
    assert!(update::stage(&work, &pkg2, "0.2.0").is_err()); // thiếu REQUIRED
}
#[test]
fn update__failed_version_reported_once_and_status() {
    let root = tmp("failed"); fs::create_dir_all(&root).unwrap();
    fs::write(root.join("failed"), "0.2.0").unwrap();
    assert_eq!(update::take_failed_version(&root).as_deref(), Some("0.2.0"));
    assert_eq!(update::take_failed_version(&root), None);
    update::set_status(&root, "downloading", "").unwrap();
    assert_eq!(update::read_status(&root).unwrap().0, "downloading");
}

// ---- tests/lua/test_night_pages.lua ----
#[test]
fn night_pages__decision_table() {
    let mut s: BTreeMap<String, i64> = BTreeMap::new();
    assert!(!night_pages::is_kept(&s)); // off by default
    let ev = night_pages::set(&mut s, true, DocKind::Paged, Some(0));
    assert_eq!(s["kopt_nightmode_document"], 1);
    assert_eq!(s["copt_nightmode_images"], 1);
    assert!(matches!(ev, Some(night_pages::NightEvent::ConfigChange { value: 1, .. })));
    // Đã đúng trạng thái thì không phát event.
    assert_eq!(night_pages::plan_apply(true, DocKind::Paged, Some(1)), None);
    // EPUB
    let ev = night_pages::set(&mut s, false, DocKind::Reflowable, Some(1));
    assert!(matches!(ev, Some(night_pages::NightEvent::ToggleNightmodeImages(false))));
    // File browser: không có document.
    assert_eq!(night_pages::plan_apply(true, DocKind::None, None), None);
    assert!(!night_pages::menu_enabled(false));
    assert!(night_pages::menu_enabled(true));
}

// ---- tests/lua/test_framebuffer.lua ----
#[test]
fn framebuffer__bgr_swap_and_region() {
    let mut src = Buffer::new(4, 3, 16); let mut dst = Buffer::new(4, 3, 24);
    src.set_px(1, 1, [0xD8, 0xE6, 0xFA, 0xFF]);
    src.set_px(2, 1, [0x11, 0x22, 0x33, 0x80]);
    copy_to_screen(&src, &mut dst, 1, 1, 2, 1, true);
    assert_eq!(dst.px(1, 1), [0xFA, 0xE6, 0xD8, 0xFF]);
    assert_eq!(dst.px(2, 1), [0x33, 0x22, 0x11, 0x80]);
    assert_eq!(dst.px(0, 1), [0, 0, 0, 0]); // ngoài rect không đổi
    assert_eq!(dst.px(3, 1), [0, 0, 0, 0]);
}
#[test]
fn framebuffer__verbatim_and_bounded() {
    let mut src = Buffer::tight(2, 2); src.set_px(0, 0, [1, 2, 3, 4]);
    let mut dst = Buffer::tight(2, 2);
    copy_to_screen(&src, &mut dst, 0, 0, 2, 2, false);
    assert_eq!(dst.px(0, 0), [1, 2, 3, 4]);
    assert_eq!(bounded_rect(4, 4, -1, -1, 3, 3), Some((0, 0, 2, 2)));
    assert_eq!(bounded_rect(4, 4, 0, 0, 0, 5), None);
    assert!(ritder_core::framebuffer::needs_swap(32, 16));
    assert!(!ritder_core::framebuffer::needs_swap(32, 0));
}

// ---- tests/lua/test_input_evdev.lua ----
fn run(tr: &mut Translator, evs: &[(u16, u16, i32)], dev: &mut DeviceState) -> Vec<(u16, i32)> {
    let mut out = Vec::new();
    for &(ty, c, v) in evs { tr.translate(dev, RawEvent { ev_type: ty, code: c, value: v }, 100.0, None, &mut out); }
    out.iter().map(|e| (e.code, e.value)).collect()
}
#[test]
fn input_evdev__hat_and_triggers() {
    let mut tr = Translator::new(); let mut dev = DeviceState::default();
    assert_eq!(run(&mut tr, &[(EV_ABS, ABS_HAT0Y, -1), (EV_SYN, 0, 0), (EV_ABS, ABS_HAT0Y, 0)], &mut dev),
        vec![(103, 1), (103, 0)]);
    assert_eq!(run(&mut tr, &[(EV_ABS, ABS_HAT0X, 1), (EV_ABS, ABS_HAT0X, -1), (EV_ABS, ABS_HAT0X, 0)], &mut dev),
        vec![(106, 1), (106, 0), (105, 1), (105, 0)]);
    let mut dev2 = DeviceState::default(); let mut tr2 = Translator::new();
    assert_eq!(run(&mut tr2, &[(EV_ABS, ABS_Z, 50), (EV_ABS, ABS_Z, 200), (EV_ABS, ABS_Z, 255), (EV_ABS, ABS_Z, 0)], &mut dev2),
        vec![(312, 1), (312, 0)]);
    assert_eq!(run(&mut tr2, &[(EV_ABS, ABS_RZ, 255)], &mut dev2), vec![(313, 1)]);
}
#[test]
fn input_evdev__passthrough_drop_and_repeat() {
    let mut tr = Translator::new(); let mut dev = DeviceState::default();
    assert_eq!(run(&mut tr, &[(EV_KEY, 305, 1), (EV_SYN, 0, 0), (4, 4, 90001), (EV_ABS, 0, 12000), (EV_KEY, 305, 0)], &mut dev),
        vec![(305, 1), (305, 0)]);
    // Kernel repeat của phím repeatable bị bỏ; của phím thường thì qua.
    assert_eq!(run(&mut tr, &[(EV_KEY, 310, 1), (EV_KEY, 310, 2), (EV_KEY, 305, 2)], &mut dev),
        vec![(310, 1), (305, 2)]);
    // Software repeat: sau 0.40s, chu kỳ 0.10s, nhả phím thì hết.
    let mut tr2 = Translator::new(); let mut dev2 = DeviceState::default();
    run(&mut tr2, &[(EV_ABS, ABS_HAT0Y, 1)], &mut dev2);
    // held được đặt theo t=100.0 của run()
    let mut out = Vec::new(); tr2.due_repeats(100.2, &mut out); assert!(out.is_empty());
    tr2.due_repeats(100.45, &mut out); assert_eq!(out.len(), 1); assert_eq!(out[0].value, KEY_REPEAT);
    out.clear(); tr2.due_repeats(100.50, &mut out); assert!(out.is_empty());
    tr2.due_repeats(100.56, &mut out); assert_eq!(out.len(), 1);
}
#[test]
fn input_evdev__event_map_defaults() {
    let m = ritder_core::event_map::default_event_map();
    assert_eq!(m[&305], "Press"); assert_eq!(m[&315], "Menu"); assert!(!m.contains_key(&316));
    assert!(ritder_core::event_map::events_for("L2").is_ok());
    assert!(ritder_core::event_map::events_for("NOPE").is_err());
}

// ---- tests/lua/test_diagnostics.lua ----
#[test]
fn diagnostics__tail_limit_and_collect() {
    let root = tmp("diag");
    let lines: Vec<String> = (1..=2000).map(|i| format!("dòng {i}")).collect();
    fs::write(root.join("crash.log"), lines.join("\n")).unwrap();
    fs::write(root.join("ritder.log"), "mở app\nthoát bình thường\n").unwrap();
    let tail = diagnostics::tail_lines(&root.join("crash.log"), 250).unwrap();
    assert!(tail.contains("dòng 2000")); assert!(!tail.contains("dòng 100\n"));
    let (path, size) = diagnostics::collect(&root, &["Ritder 9.9.9 (thử nghiệm)".into(), "Màn hình: 1024x768".into()]).unwrap();
    assert!(size > 0);
    let text = fs::read_to_string(&path).unwrap();
    assert!(text.contains("Ritder 9.9.9")); assert!(text.contains("thoát bình thường"));
    assert!(text.contains("(không có)")); // log thiếu được báo, không lỗi
}
#[test]
fn diagnostics__crash_code_once() {
    let root = tmp("crashcode");
    fs::write(root.join("crashed"), "139\n").unwrap();
    assert_eq!(diagnostics::take_crash_code(&root), Some(139));
    assert_eq!(diagnostics::take_crash_code(&root), None);
}

// ---- tests/shell/test_install.sh ----
fn setup_install(tag: &str) -> (PathBuf, PathBuf, PathBuf) {
    let app = tmp(tag);
    let userdata = app.join("userdata"); let upd = userdata.join("update");
    let staging = upd.join("staging");
    fs::create_dir_all(staging.join("frontend")).unwrap();
    fs::create_dir_all(app.join("frontend")).unwrap(); fs::create_dir_all(app.join("libs")).unwrap();
    fs::write(app.join("reader.lua"), "old reader").unwrap();
    fs::write(app.join("luajit"), "old luajit").unwrap();
    fs::write(app.join("libs/lib.so"), "old lib").unwrap();
    fs::write(userdata.join("settings.reader.lua"), "my settings").unwrap();
    fs::write(staging.join("reader.lua"), "new reader").unwrap();
    fs::write(staging.join("luajit"), "new luajit").unwrap();
    fs::write(staging.join("frontend/new.lua"), "brand new").unwrap();
    fs::write(upd.join("ready"), "0.2.0").unwrap();
    (app, userdata, upd)
}
#[test]
fn install__normal_install_and_rollback() {
    let (app, userdata, upd) = setup_install("inst1");
    install::install_staged(&app, &userdata).unwrap();
    assert_eq!(fs::read_to_string(app.join("reader.lua")).unwrap(), "new reader");
    assert_eq!(fs::read_to_string(app.join("frontend/new.lua")).unwrap(), "brand new");
    assert_eq!(fs::read_to_string(app.join("libs/lib.so")).unwrap(), "old lib");
    assert_eq!(fs::read_to_string(userdata.join("settings.reader.lua")).unwrap(), "my settings");
    assert_eq!(fs::read_to_string(upd.join("backup/reader.lua")).unwrap(), "old reader");
    assert_eq!(fs::read_to_string(upd.join("added.txt")).unwrap().trim(), "frontend/new.lua");
    assert_eq!(fs::read_to_string(upd.join("pending")).unwrap().trim(), "0.2.0");
    assert!(!upd.join("staging").exists()); assert!(!upd.join("ready").exists()); assert!(!upd.join("installing").exists());
    install::restore_backup(&app, &userdata).unwrap();
    assert_eq!(fs::read_to_string(app.join("reader.lua")).unwrap(), "old reader");
    assert_eq!(fs::read_to_string(app.join("luajit")).unwrap(), "old luajit");
    assert!(!app.join("frontend/new.lua").exists());
    assert!(!upd.join("pending").exists());
}
#[test]
fn install__rollback_on_failure() {
    let (app, userdata, upd) = setup_install("inst2");
    // Một file chắn chỗ thư mục cần tạo: bước di chuyển sẽ lỗi giữa chừng.
    fs::remove_dir_all(app.join("frontend")).unwrap();
    fs::write(app.join("frontend"), "blocker").unwrap();
    assert!(install::install_staged(&app, &userdata).is_err());
    assert_eq!(fs::read_to_string(app.join("reader.lua")).unwrap(), "old reader");
    assert_eq!(fs::read_to_string(app.join("luajit")).unwrap(), "old luajit");
    assert_eq!(fs::read_to_string(upd.join("failed")).unwrap().trim(), "0.2.0");
    assert!(!upd.join("pending").exists());
    assert!(userdata.join("update.log").exists());
}
#[test]
fn install__interrupted_install_undone() {
    let (app, userdata, upd) = setup_install("inst3");
    fs::write(upd.join("installing"), "0.2.0").unwrap();
    fs::create_dir_all(upd.join("backup")).unwrap();
    fs::write(upd.join("backup/reader.lua"), "old reader").unwrap();
    fs::write(app.join("reader.lua"), "half new").unwrap();
    fs::write(upd.join("added.txt"), "frontend/new.lua\n").unwrap();
    fs::write(app.join("frontend/new.lua"), "half new").unwrap();
    install::restore_backup(&app, &userdata).unwrap();
    assert_eq!(fs::read_to_string(app.join("reader.lua")).unwrap(), "old reader");
    assert!(!app.join("frontend/new.lua").exists());
    assert!(!upd.join("installing").exists());
}
#[test]
fn install__logging_history_trim_800() {
    let root = tmp("log800");
    let p = root.join("ritder.log");
    let lines: Vec<String> = (0..900).map(|i| format!("line {i}")).collect();
    fs::write(&p, lines.join("\n") + "\n").unwrap();
    ritder_core::logging::rotate_logs(&root);
    let kept = fs::read_to_string(&p).unwrap();
    assert_eq!(kept.lines().count(), 800);
    assert_eq!(ritder_core::logging::session_end_message(42).0, "thoát để cài bản cập nhật (mã 42)");
    assert!(ritder_core::logging::session_end_message(1).1);
}
