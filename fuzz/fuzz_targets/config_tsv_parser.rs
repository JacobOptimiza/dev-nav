#![no_main]

use dev_nav::config::Config;
use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    if let Ok(contents) = std::str::from_utf8(data) {
        let _ = Config::parse_tsv(contents);
    }
});
