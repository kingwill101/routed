#[test]
fn direct_callback_payload_enqueues_and_signals_callback() {
    let _callback_guard = lock_test_callback_state();

    let direct_bridge = create_direct_bridge(Some(test_direct_callback));
    let _response_rx = register_pending_request(&direct_bridge, 42);

    emit_direct_callback_payload(&direct_bridge, 42, vec![1, 2, 3, 4]).expect("emit payload");

    let queued = direct_bridge.queued_payloads.lock();
    assert_eq!(queued.len(), 1);
    assert_eq!(queued.front().expect("queued payload").request_id, 42);
    assert_eq!(
        queued.front().expect("queued payload").payload.as_slice(),
        &[1, 2, 3, 4]
    );
    drop(queued);

    assert_eq!(TEST_CALLBACK_INVOCATIONS.load(AtomicOrdering::SeqCst), 1);
    assert_eq!(
        TEST_CALLBACK_LAST_REQUEST_ID.load(AtomicOrdering::SeqCst),
        42
    );
}

#[test]
fn direct_callback_payload_coalesces_wakeups_while_queue_is_non_empty() {
    let _callback_guard = lock_test_callback_state();

    let direct_bridge = create_direct_bridge(Some(test_direct_callback));
    let _response_rx = register_pending_request(&direct_bridge, 7);

    emit_direct_callback_payload(&direct_bridge, 7, vec![1]).expect("first payload");
    emit_direct_callback_payload(&direct_bridge, 7, vec![2]).expect("second payload");

    assert_eq!(TEST_CALLBACK_INVOCATIONS.load(AtomicOrdering::SeqCst), 1);
    assert_eq!(
        TEST_CALLBACK_LAST_REQUEST_ID.load(AtomicOrdering::SeqCst),
        7
    );

    direct_bridge.queued_payloads.lock().clear();
    emit_direct_callback_payload(&direct_bridge, 7, vec![3]).expect("third payload");

    assert_eq!(TEST_CALLBACK_INVOCATIONS.load(AtomicOrdering::SeqCst), 2);
}

#[test]
fn stopping_direct_bridge_waits_for_in_flight_callback() {
    let _callback_guard = lock_test_callback_state();

    let direct_bridge = create_direct_bridge(Some(blocking_test_direct_callback));
    let _response_rx = register_pending_request(&direct_bridge, 5);
    let callback_bridge = direct_bridge.clone();
    let callback_thread = std::thread::spawn(move || {
        emit_direct_callback_payload(&callback_bridge, 5, vec![1])
            .expect("blocking callback payload");
    });

    for _ in 0..100 {
        if TEST_CALLBACK_INVOCATIONS.load(AtomicOrdering::SeqCst) == 1 {
            break;
        }
        std::thread::sleep(Duration::from_millis(1));
    }
    assert_eq!(TEST_CALLBACK_INVOCATIONS.load(AtomicOrdering::SeqCst), 1);

    let stop_bridge = direct_bridge.clone();
    let stop_thread = std::thread::spawn(move || stop_direct_bridge(&stop_bridge));
    std::thread::sleep(Duration::from_millis(5));
    TEST_BLOCKING_CALLBACK_RELEASED.store(true, AtomicOrdering::SeqCst);

    callback_thread.join().expect("callback should finish");
    stop_thread.join().expect("stop should finish");
    assert!(direct_bridge.callback_state.lock().stopping);
    assert_eq!(direct_bridge.callback_state.lock().in_flight, 0);
}

#[test]
fn direct_callback_payload_rejects_missing_or_stopped_request() {
    let direct_bridge = create_direct_bridge(None);

    let missing_error =
        emit_direct_callback_payload(&direct_bridge, 99, vec![1]).expect_err("missing request");
    assert!(missing_error.contains("missing request id"));

    let _response_rx = register_pending_request(&direct_bridge, 99);
    direct_bridge.stopped.store(true, Ordering::Release);
    let stopped_error =
        emit_direct_callback_payload(&direct_bridge, 99, vec![1]).expect_err("stopped bridge");
    assert!(stopped_error.contains("stopping"));
}

#[test]
fn push_direct_response_frame_routes_payload_to_pending_request() {
    let direct_bridge = create_direct_bridge(None);
    let mut response_rx = register_pending_request(&direct_bridge, 7);
    let mut handle = ProxyServerHandle {
        shutdown_tx: None,
        join_handle: None,
        direct_bridge: Some(direct_bridge),
    };
    let handle_ptr = &mut handle as *mut ProxyServerHandle;

    let payload = vec![10_u8, 20_u8, 30_u8];
    let pushed = unsafe {
        server_native_push_direct_response_frame(
            handle_ptr,
            7,
            payload.as_ptr(),
            payload.len() as u64,
        )
    };
    assert_eq!(pushed, 1);
    assert_eq!(
        response_rx.try_recv().expect("payload should be delivered"),
        payload
    );

    let unknown =
        unsafe { server_native_push_direct_response_frame(handle_ptr, 8, payload.as_ptr(), 3) };
    assert_eq!(unknown, 0);
}

#[test]
fn poll_direct_request_frame_returns_and_frees_payload() {
    let direct_bridge = create_direct_bridge(None);
    direct_bridge
        .queued_payloads
        .lock()
        .push_back(QueuedDirectPayload {
            request_id: 17,
            payload: vec![1_u8, 3_u8, 5_u8, 7_u8],
        });

    let mut handle = ProxyServerHandle {
        shutdown_tx: None,
        join_handle: None,
        direct_bridge: Some(direct_bridge),
    };
    let handle_ptr = &mut handle as *mut ProxyServerHandle;

    let mut out_request_id = 0_u64;
    let mut out_payload: *mut u8 = std::ptr::null_mut();
    let mut out_payload_len = 0_u64;
    let result = unsafe {
        server_native_poll_direct_request_frame(
            handle_ptr,
            0,
            &mut out_request_id as *mut u64,
            &mut out_payload as *mut *mut u8,
            &mut out_payload_len as *mut u64,
        )
    };

    assert_eq!(result, 1);
    assert_eq!(out_request_id, 17);
    assert!(!out_payload.is_null());
    assert_eq!(out_payload_len, 4);

    let payload =
        unsafe { std::slice::from_raw_parts(out_payload as *const u8, out_payload_len as usize) };
    assert_eq!(payload, &[1_u8, 3_u8, 5_u8, 7_u8]);

    unsafe {
        server_native_free_direct_request_payload(out_payload, out_payload_len);
    }
}
use super::*;
use std::sync::atomic::Ordering as AtomicOrdering;
use std::time::Duration;
