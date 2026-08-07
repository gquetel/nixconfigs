
# Appended to hermes' tools/daemon_pool.py.
#
# Replaces _adjust_thread_count, which reads self._initializer and calls
# _worker with the 3.8-3.13 argument order. Python 3.14 moved both behind a
# worker-context object, so every submit() raises AttributeError without this.
def _adjust_thread_count_compat(self) -> None:
    if self._idle_semaphore.acquire(timeout=0):
        return

    def weakref_cb(_, q=self._work_queue):
        q.put(None)

    num_threads = len(self._threads)
    if num_threads >= self._max_workers:
        return

    if hasattr(self, "_create_worker_context"):  # 3.14+
        args = (
            weakref.ref(self, weakref_cb),
            self._create_worker_context(),
            self._work_queue,
        )
    else:
        args = (
            weakref.ref(self, weakref_cb),
            self._work_queue,
            self._initializer,
            self._initargs,
        )

    # daemon=True, and no _threads_queues entry, so a wedged worker cannot
    # hold interpreter exit open.
    t = threading.Thread(
        name="%s_%d" % (self._thread_name_prefix or self, num_threads),
        target=_worker,
        args=args,
        daemon=True,
    )
    t.start()
    self._threads.add(t)


DaemonThreadPoolExecutor._adjust_thread_count = _adjust_thread_count_compat
