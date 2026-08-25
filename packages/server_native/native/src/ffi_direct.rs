use crate::*;

#[no_mangle]
/// Stops a proxy server previously created by [`server_native_start_proxy_server`].
///
/// This function consumes the handle pointer and must not be called twice with
/// the same pointer.
///
/// # Safety
///
/// `handle` must be either null or a pointer returned by
/// [`server_native_start_proxy_server`] that has not yet been freed.
pub unsafe extern "C" fn server_native_stop_proxy_server(handle: *mut ProxyServerHandle) {
    if handle.is_null() {
        return;
    }

    let mut handle = unsafe { Box::from_raw(handle) };
    if let Some(direct_bridge) = handle.direct_bridge.as_ref() {
        stop_direct_bridge(direct_bridge);
    }
    if let Some(tx) = handle.shutdown_tx.take() {
        let _ = tx.send(());
    }
    if let Some(join_handle) = handle.join_handle.take() {
        let _ = join_handle.join();
    }
}

/// Stops the direct bridge without allowing a callback to race handle teardown.
pub(crate) fn stop_direct_bridge(direct_bridge: &Arc<DirectRequestBridge>) {
    direct_bridge.stopped.store(true, Ordering::Release);

    let mut callback_state = direct_bridge.callback_state.lock();
    callback_state.stopping = true;
    while callback_state.in_flight != 0 {
        direct_bridge.callback_state_cv.wait(&mut callback_state);
    }
    callback_state.callback = None;
    drop(callback_state);

    direct_bridge.queued_payloads.lock().clear();
    direct_bridge.queued_payloads_cv.notify_all();
    direct_bridge.pending.lock().clear();
}

#[no_mangle]
/// Pushes a direct-callback response frame for a pending request.
///
/// Returns `1` on success, `0` when the request is unknown or arguments are
/// invalid.
///
/// # Safety
///
/// `handle` must be a valid pointer returned by
/// [`server_native_start_proxy_server`]. `response_payload` must reference
/// `response_payload_len` readable bytes for the duration of this call.
pub unsafe extern "C" fn server_native_push_direct_response_frame(
    handle: *mut ProxyServerHandle,
    request_id: u64,
    response_payload: *const u8,
    response_payload_len: u64,
) -> u8 {
    if handle.is_null() || response_payload.is_null() {
        return 0;
    }

    let handle_ref = unsafe { &*handle };
    let Some(direct_bridge) = handle_ref.direct_bridge.as_ref() else {
        return 0;
    };
    if direct_bridge.stopped.load(Ordering::Acquire) {
        return 0;
    }

    let Ok(response_payload_len) = usize::try_from(response_payload_len) else {
        return 0;
    };
    let response = unsafe { std::slice::from_raw_parts(response_payload, response_payload_len) };
    let response_tx = {
        let pending = direct_bridge.pending.lock();
        let Some(entry) = pending.get(&request_id) else {
            return 0;
        };
        entry.response_tx.clone()
    };
    if response_tx.send(response.to_vec()).is_err() {
        return 0;
    }
    1
}

#[no_mangle]
/// Polls one queued direct-request frame produced by Rust.
///
/// Returns `1` and writes outputs when a frame is available, otherwise `0`.
///
/// # Safety
///
/// `handle` must be a valid pointer returned by
/// [`server_native_start_proxy_server`]. `out_request_id`, `out_payload`, and
/// `out_payload_len` must be valid writable pointers.
pub unsafe extern "C" fn server_native_poll_direct_request_frame(
    handle: *mut ProxyServerHandle,
    timeout_millis: u32,
    out_request_id: *mut u64,
    out_payload: *mut *mut u8,
    out_payload_len: *mut u64,
) -> u8 {
    if handle.is_null()
        || out_request_id.is_null()
        || out_payload.is_null()
        || out_payload_len.is_null()
    {
        return 0;
    }

    let handle_ref = unsafe { &*handle };
    let Some(direct_bridge) = handle_ref.direct_bridge.as_ref() else {
        return 0;
    };
    if direct_bridge.stopped.load(Ordering::Acquire) {
        return 0;
    }

    let mut queued = direct_bridge.queued_payloads.lock();
    if queued.is_empty() && timeout_millis != 0 {
        let timeout = Duration::from_millis(timeout_millis as u64);
        let _ = direct_bridge
            .queued_payloads_cv
            .wait_for(&mut queued, timeout);
    }

    let Some(item) = queued.pop_front() else {
        return 0;
    };
    drop(queued);

    let mut payload = item.payload.into_boxed_slice();
    let Ok(payload_len) = u64::try_from(payload.len()) else {
        return 0;
    };
    let payload_ptr = payload.as_mut_ptr();
    std::mem::forget(payload);

    unsafe {
        *out_request_id = item.request_id;
        *out_payload = payload_ptr;
        *out_payload_len = payload_len;
    }

    1
}

#[no_mangle]
/// Frees one payload previously returned by
/// [`server_native_poll_direct_request_frame`].
///
/// # Safety
///
/// `payload` must be a pointer returned by
/// [`server_native_poll_direct_request_frame`] with matching `payload_len`.
pub unsafe extern "C" fn server_native_free_direct_request_payload(
    payload: *mut u8,
    payload_len: u64,
) {
    if payload.is_null() {
        return;
    }
    let Ok(payload_len) = usize::try_from(payload_len) else {
        return;
    };
    unsafe {
        let _ = Vec::from_raw_parts(payload, payload_len, payload_len);
    }
}

#[no_mangle]
/// Compatibility alias for [`server_native_push_direct_response_frame`].
///
/// # Safety
///
/// Same safety contract as [`server_native_push_direct_response_frame`].
pub unsafe extern "C" fn server_native_complete_direct_request(
    handle: *mut ProxyServerHandle,
    request_id: u64,
    response_payload: *const u8,
    response_payload_len: u64,
) -> u8 {
    unsafe {
        server_native_push_direct_response_frame(
            handle,
            request_id,
            response_payload,
            response_payload_len,
        )
    }
}
