pragma Singleton
import QtQuick
import Quickshell

// Runs queued jobs one at a time while the shell is idle (no module open),
// with a gap between them, starting a few seconds after start-up. Used to
// build heavy UI (Control Center pages) ahead of time so opening them never
// has to create objects mid-animation.
//
// A job is { label, run: function() -> optional Loader }. If it returns a
// Loader, the next job waits until that Loader has finished loading.
Singleton {
    id: root

    property var _queue: []
    property var _waitingOn: null
    property bool _started: false

    readonly property bool idle: Visibilities.currentActiveModule === ""

    function enqueue(job, first) {
        if (first)
            _queue.unshift(job);
        else
            _queue.push(job);
        _kick(gapTimer.interval);
    }

    function _kick(delay) {
        if (!_started || gapTimer.running || _queue.length === 0)
            return;
        gapTimer.interval = delay;
        gapTimer.start();
    }

    function _runNext() {
        if (_waitingOn) {
            if (_waitingOn.status === Loader.Loading) {
                _kick(100);
                return;
            }
            _waitingOn = null;
        }
        if (_queue.length === 0)
            return;
        if (!idle) {
            _kick(1000);
            return;
        }
        const job = _queue.shift();
        PerfProbe.mark("warmup " + job.label);
        let result = null;
        try {
            result = job.run();
        } catch (e) {
            console.warn("IdleWork job failed:", job.label, e);
        }
        PerfProbe.done("warmup " + job.label);
        if (result && result.status !== undefined)
            _waitingOn = result;
        _kick(150);
    }

    Timer {
        id: startTimer
        interval: 4000
        running: true
        onTriggered: {
            root._started = true;
            root._kick(0);
        }
    }

    Timer {
        id: gapTimer
        interval: 150
        onTriggered: root._runNext()
    }
}
