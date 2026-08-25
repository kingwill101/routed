use super::*;
use std::sync::atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering as AtomicOrdering};
use std::time::Duration;

pub(super) static TEST_CALLBACK_INVOCATIONS: AtomicUsize = AtomicUsize::new(0);
pub(super) static TEST_CALLBACK_LAST_REQUEST_ID: AtomicU64 = AtomicU64::new(0);
pub(super) static TEST_BLOCKING_CALLBACK_RELEASED: AtomicBool = AtomicBool::new(false);
pub(super) static TEST_CALLBACK_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

pub(super) extern "C" fn test_direct_callback(
    request_id: u64,
    _payload: *const u8,
    _payload_len: u64,
) {
    TEST_CALLBACK_INVOCATIONS.fetch_add(1, AtomicOrdering::SeqCst);
    TEST_CALLBACK_LAST_REQUEST_ID.store(request_id, AtomicOrdering::SeqCst);
}

pub(super) extern "C" fn blocking_test_direct_callback(
    request_id: u64,
    _payload: *const u8,
    _payload_len: u64,
) {
    TEST_CALLBACK_INVOCATIONS.fetch_add(1, AtomicOrdering::SeqCst);
    TEST_CALLBACK_LAST_REQUEST_ID.store(request_id, AtomicOrdering::SeqCst);
    while !TEST_BLOCKING_CALLBACK_RELEASED.load(AtomicOrdering::SeqCst) {
        std::thread::sleep(Duration::from_millis(1));
    }
}

pub(super) fn lock_test_callback_state() -> std::sync::MutexGuard<'static, ()> {
    let guard = TEST_CALLBACK_LOCK.lock().expect("test callback lock");
    TEST_CALLBACK_INVOCATIONS.store(0, AtomicOrdering::SeqCst);
    TEST_CALLBACK_LAST_REQUEST_ID.store(0, AtomicOrdering::SeqCst);
    TEST_BLOCKING_CALLBACK_RELEASED.store(false, AtomicOrdering::SeqCst);
    guard
}

pub(super) fn create_direct_bridge(
    callback: Option<DirectRequestCallback>,
) -> Arc<DirectRequestBridge> {
    Arc::new(DirectRequestBridge {
        callback_state: Mutex::new(DirectCallbackState {
            callback,
            stopping: false,
            in_flight: 0,
        }),
        callback_state_cv: Condvar::new(),
        next_request_id: AtomicU64::new(1),
        stopped: AtomicBool::new(false),
        pending: Mutex::new(HashMap::new()),
        queued_payloads: Mutex::new(VecDeque::new()),
        queued_payloads_cv: Condvar::new(),
    })
}

pub(super) fn register_pending_request(
    direct_bridge: &Arc<DirectRequestBridge>,
    request_id: u64,
) -> mpsc::UnboundedReceiver<Vec<u8>> {
    let (response_tx, response_rx) = mpsc::unbounded_channel::<Vec<u8>>();
    direct_bridge
        .pending
        .lock()
        .insert(request_id, PendingDirectRequest { response_tx });
    response_rx
}
