fn main() {
    println!("cargo:rerun-if-env-changed=CUDARC_CUDA_VERSION");

    // Only validate when the cuda feature is active for this crate.
    if std::env::var_os("CARGO_FEATURE_CUDA").is_none() {
        return;
    }

    let cudarc_version = std::env::var("CUDARC_CUDA_VERSION").ok();

    // Detect the driver's maximum supported CUDA version from nvidia-smi.
    let driver_version = detect_driver_cuda_version();

    // Detect the toolkit version from nvcc (what cudarc uses when
    // CUDARC_CUDA_VERSION is not set).
    let toolkit_version = detect_toolkit_cuda_version();

    match (&driver_version, &toolkit_version) {
        (Some(driver), Some(toolkit)) if driver != toolkit => {
            if cudarc_version.is_none() {
                println!(
                    "cargo:warning=CUDA version mismatch: driver supports {driver} \
                     but toolkit (nvcc) reports {toolkit}. \
                     cudarc will be compiled for {toolkit}, which may panic at runtime \
                     if the driver does not expose CUDA {toolkit} symbols. \
                     Run builds via `npx tsx scripts/dev.ts` to auto-pin to the \
                     driver version, or set CUDARC_CUDA_VERSION={} manually.",
                    to_cudarc_format(driver)
                );
            }
        }
        _ => {}
    }

    if let Some(version) = &cudarc_version {
        println!("cargo:rustc-env=CUDARC_CUDA_VERSION_PINNED={version}");
    }
}

/// Parses the CUDA version supported by the installed driver via `nvidia-smi`.
/// Returns a string like "13.1".
fn detect_driver_cuda_version() -> Option<String> {
    let output = std::process::Command::new("nvidia-smi").output().ok()?;
    if !output.status.success() {
        return None;
    }
    let stdout = String::from_utf8_lossy(&output.stdout);
    // The header line contains e.g. "CUDA Version: 13.1"
    let line = stdout.lines().find(|l| l.contains("CUDA Version:"))?;
    let version = line
        .split("CUDA Version:")
        .nth(1)?
        .split_whitespace()
        .next()?
        .to_string();
    Some(version)
}

/// Parses the CUDA version from `nvcc --version`.
/// Returns a string like "13.2".
fn detect_toolkit_cuda_version() -> Option<String> {
    let output = std::process::Command::new("nvcc")
        .arg("--version")
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    let stdout = String::from_utf8_lossy(&output.stdout);
    // Line looks like: "Cuda compilation tools, release 13.2, V13.2.51"
    let line = stdout.lines().find(|l| l.contains("release"))?;
    let after = line.split("release").nth(1)?;
    let version = after.split(',').next()?.trim().to_string();
    Some(version)
}

/// Converts "13.1" to "13010" (the format expected by CUDARC_CUDA_VERSION).
fn to_cudarc_format(version: &str) -> String {
    let mut parts = version.splitn(2, '.');
    let major = parts.next().unwrap_or("0");
    let minor = parts.next().unwrap_or("0");
    format!("{major}0{minor}0")
}
