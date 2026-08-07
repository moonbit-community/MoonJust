use std::{collections::BTreeMap, io::Read, process::ExitCode};

fn main() -> ExitCode {
    std::env::set_var("KEY11", "ambient");
    let mut input = Vec::new();
    if std::io::stdin().read_to_end(&mut input).is_err() {
        return ExitCode::from(2);
    }
    let mut values = BTreeMap::new();
    for entry in dotenvy::from_read_iter(input.as_slice()) {
        let (key, value) = match entry {
            Ok(entry) => entry,
            Err(_) => return ExitCode::FAILURE,
        };
        values.insert(key, value);
    }
    for (key, value) in values {
        println!("{key}={}", hex::encode(value));
    }
    ExitCode::SUCCESS
}

mod hex {
    pub(super) fn encode(value: String) -> String {
        const DIGITS: &[u8; 16] = b"0123456789abcdef";
        let mut output = String::with_capacity(value.len() * 2);
        for byte in value.bytes() {
            output.push(DIGITS[(byte >> 4) as usize] as char);
            output.push(DIGITS[(byte & 0xf) as usize] as char);
        }
        output
    }
}
