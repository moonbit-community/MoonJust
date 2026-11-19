///|
// moonbitlang/x/time exposes its POSIX rule parser through Zone::from_tzif.
// In a TZif with no transitions the footer applies to every instant (RFC 9636
// §3.2). The v1 and v3 blocks are identical when both transition tables are empty.
let rule_only_tzif_prefix : Bytes = {
  let block = Buffer()
  block.write_bytes(b"TZif3")
  for _ in 0..<15 {
    block.write_byte(b'\x00')
  }
  // UT flags, standard flags, leaps, transitions, time types, designation bytes.
  for count in [0U, 0U, 0U, 0U, 1U, 4U] {
    block.write_uint_be(count)
  }
  block.write_bytes(b"\x00\x00\x00\x00\x00\x00UTC\x00")
  let data = block.to_bytes()
  data + data + b"\n"
}

///|
fn posix_zone(rule : String) -> @time.Zone? {
  if rule.is_empty() || rule.has_prefix(":") || rule.has_prefix("/") {
    return None
  }
  let data = rule_only_tzif_prefix + @utf8.encode(rule) + b"\n"
  Some(@time.Zone::from_tzif(rule, data)) catch {
    _ => None
  }
}

///|
let unix_zone_cache : Ref[(String, @time.Zone)?] = Ref(None)

///|
async fn unix_local_zone(name : String) -> @time.Zone {
  if unix_zone_cache.val is Some((previous, zone)) && previous == name {
    return zone
  }
  let zone = match posix_zone(name) {
    Some(zone) => zone
    None => {
      let id = name.strip_prefix(":").unwrap_or(name[:])
      let path = if name.is_empty() {
        "/etc/localtime"
      } else if id.has_prefix("/") {
        id.to_owned()
      } else {
        "/usr/share/zoneinfo/" + id.to_owned()
      }
      let data = @async_fs.read_binary(path) catch {
        // With no explicit DST rules or matching zoneinfo entry, just's Unix
        // clock falls back to the system zone. Preserve other I/O errors.
        @os_error.OsError(NotFound, ..) if !name.is_empty() &&
          !name.has_prefix(":") &&
          !name.has_prefix("/") => @async_fs.read_binary("/etc/localtime")
        error => raise error
      }
      @time.Zone::from_tzif(name, data)
    }
  }
  unix_zone_cache.val = Some((name, zone))
  zone
}
