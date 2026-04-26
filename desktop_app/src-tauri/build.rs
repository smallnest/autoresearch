use std::fs;
use std::path::Path;

fn main() {
    let manifest_dir = std::env::var("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR not set");
    let manifest = Path::new(&manifest_dir);

    // Workspace root: src-tauri/ -> desktop_app/ -> autoresearch root
    let workspace_root = manifest
        .parent() // desktop_app/
        .and_then(|p| p.parent()) // autoresearch root
        .expect("Cannot determine workspace root from CARGO_MANIFEST_DIR");

    let resources_dir = manifest.join("resources").join("runtime");

    // Clean and recreate resources directory
    if resources_dir.exists() {
        fs::remove_dir_all(&resources_dir).expect("Failed to clean resources/runtime directory");
    }
    fs::create_dir_all(&resources_dir).expect("Failed to create resources/runtime directory");

    // Copy individual files
    let files_to_copy = ["run.sh", "program.md"];
    for file in &files_to_copy {
        let src = workspace_root.join(file);
        let dst = resources_dir.join(file);
        if src.exists() {
            fs::copy(&src, &dst).unwrap_or_else(|e| {
                panic!("Failed to copy {}: {}", src.display(), e)
            });
            println!("cargo:rerun-if-changed={}", src.display());
        } else {
            println!(
                "cargo:warning=Source file not found, skipping: {}",
                src.display()
            );
        }
    }

    // Copy directories recursively
    let dirs_to_copy = ["lib", "agents"];
    for dir in &dirs_to_copy {
        let src = workspace_root.join(dir);
        let dst = resources_dir.join(dir);
        if src.is_dir() {
            copy_dir_recursive(&src, &dst).unwrap_or_else(|e| {
                panic!("Failed to copy directory {}: {}", src.display(), e)
            });
            println!("cargo:rerun-if-changed={}", src.display());
        } else {
            println!(
                "cargo:warning=Source directory not found, skipping: {}",
                src.display()
            );
        }
    }

    // Generate version.txt by parsing version from tauri.conf.json
    let tauri_conf_path = manifest.join("tauri.conf.json");
    let version = if tauri_conf_path.exists() {
        let content =
            fs::read_to_string(&tauri_conf_path).expect("Failed to read tauri.conf.json");
        extract_version(&content).unwrap_or_else(|| "0.0.0".to_string())
    } else {
        "0.0.0".to_string()
    };
    fs::write(resources_dir.join("version.txt"), &version)
        .expect("Failed to write version.txt");
    println!("cargo:rerun-if-changed={}", tauri_conf_path.display());

    println!("cargo:warning=Runtime resources prepared (version {version})");

    tauri_build::build()
}

/// Recursively copy a directory and all its contents.
fn copy_dir_recursive(src: &Path, dst: &Path) -> std::io::Result<()> {
    fs::create_dir_all(dst)?;
    for entry in fs::read_dir(src)? {
        let entry = entry?;
        let src_path = entry.path();
        let dst_path = dst.join(entry.file_name());
        if src_path.is_dir() {
            copy_dir_recursive(&src_path, &dst_path)?;
        } else {
            fs::copy(&src_path, &dst_path)?;
        }
    }
    Ok(())
}

/// Extract the "version" field value from tauri.conf.json JSON content.
fn extract_version(json_content: &str) -> Option<String> {
    // Simple parse: look for "version": "X.Y.Z" pattern
    for line in json_content.lines() {
        let trimmed = line.trim();
        if let Some(rest) = trimmed.strip_prefix("\"version\"") {
            if let Some(value_part) = rest.split(':').nth(1) {
                let value = value_part.trim().trim_matches(',').trim_matches('"');
                if !value.is_empty() {
                    return Some(value.to_string());
                }
            }
        }
    }
    None
}
