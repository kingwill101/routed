use crate::*;

/// Converts nullable C string pointer into owned UTF-8 Rust string.
pub(crate) fn c_string_to_string(value: *const c_char) -> Option<String> {
    if value.is_null() {
        return None;
    }
    let value = unsafe { CStr::from_ptr(value) };
    value.to_str().ok().map(ToString::to_string)
}
