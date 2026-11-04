# Build the dependency-free Rust supervisor for the Brick Pro.
# The musl target produces a self-contained ARM64 executable; it runs before
# KOReader and therefore does not depend on the firmware's old glibc.
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$cargo = Join-Path $env:USERPROFILE ".cargo\bin\cargo.exe"
if (-not (Test-Path $cargo)) { $cargo = "cargo" }
$env:RUSTFLAGS = "-C linker=rust-lld"
& $cargo build --release --target aarch64-unknown-linux-musl --manifest-path (Join-Path $root "rust\ritder-launcher\Cargo.toml")
if ($LASTEXITCODE -ne 0) { throw "Rust ARM64 build failed" }
Write-Host "Built rust\ritder-launcher\target\aarch64-unknown-linux-musl\release\ritder-launcher"
