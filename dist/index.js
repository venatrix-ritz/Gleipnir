const manifest = { "name": "Gleipnir" };
const API_VERSION = 2;
const internalAPIConnection = window.__DECKY_SECRET_INTERNALS_DO_NOT_USE_OR_YOU_WILL_BE_FIRED_deckyLoaderAPIInit;
if (!internalAPIConnection) {
    throw new Error('[@decky/api]: Failed to connect to loader API.');
}
let api;
try {
    api = internalAPIConnection.connect(API_VERSION, manifest.name);
} catch {
    api = internalAPIConnection.connect(1, manifest.name);
}
const call = api.call;
const toaster = api.toaster;
const definePlugin = (fn) => (...args) => fn(...args);

const getStatus = () => call("get_status");
const install = () => call("install");
const uninstall = () => call("uninstall");
const setEnabled = (enabled) => call("set_enabled", enabled);
const startTest = () => call("start_test");
const cancelTest = () => call("cancel_test");
const getTest = () => call("get_test");
const getLog = (lines) => call("get_log", lines);
const restoreNow = () => call("restore_now");
const setSleepFloor = (value) => call("set_sleep_floor", value);

const h = SP_JSX.jsx;
const hs = SP_JSX.jsxs;
const mono = (text) => h("div", { style: { whiteSpace: "pre-wrap", fontFamily: "monospace", fontSize: "11px", lineHeight: "1.35" }, children: text });

function describeState(s) {
    const d = s.daemon || {};
    if (!s.installed) return "Not installed";
    if (s.active !== "active") return "Stopped (charging is not limited)";
    if (!d.verified) return "Watching only: not verified yet. Run the test below.";
    return d.limit !== undefined && d.limit <= 1000 ? "Armed: holding the battery at 80%" : "Armed: will hold the battery at 80%";
}

function describeBattery(d) {
    if (!d || d.capacity === undefined) return "No battery data";
    const mA = Math.round(Math.abs(d.current_ua || 0) / 1000);
    return `${d.capacity}% · ${d.status} · ${mA} mA · ${((d.temp_dc || 0) / 10).toFixed(1)} °C · ${d.health}`;
}

function Content() {
    const [status, setStatus] = SP_REACT.useState({ installed: false, active: "", daemon: {}, test: {}, error: "" });
    const [test, setTest] = SP_REACT.useState({ running: false, tail: [], verdict: "" });
    const [log, setLog] = SP_REACT.useState(null);
    const [busy, setBusy] = SP_REACT.useState(false);

    const refresh = SP_REACT.useCallback(async () => {
        try {
            const s = await getStatus();
            if (s) setStatus(s);
            if (s && s.test && (s.test.running || s.test.finished)) {
                const t = await getTest();
                if (t) setTest(t);
            }
        } catch (e) {
            console.error("[gleipnir] refresh failed:", e);
        }
    }, []);

    SP_REACT.useEffect(() => {
        refresh();
        const interval = setInterval(refresh, 2000);
        return () => clearInterval(interval);
    }, [refresh]);

    const act = async (fn, okTitle) => {
        setBusy(true);
        try {
            const res = await fn();
            if (res && res.installed !== undefined) setStatus(res);
            if (okTitle) toaster.toast({ title: "Gleipnir", body: okTitle });
        } catch (e) {
            toaster.toast({ title: "Gleipnir error", body: String(e) });
        } finally {
            setBusy(false);
        }
    };

    const showLog = async () => {
        try {
            const r = await getLog(15);
            setLog(r && r.lines ? r.lines : []);
        } catch (e) {
            setLog([String(e)]);
        }
    };

    const d = status.daemon || {};
    const plugged = d.usb_online === 1;
    const verdictText = { pass: "PASS: the limit works on this kernel and charging resumed after release", fail: "FAIL: the limit had no clear effect, so the daemon stays watch-only", aborted: "Aborted: charging limit restored, nothing verified", refused: "Not run: conditions not met (see output)" }[test.verdict] || "";

    return hs(SP_JSX.Fragment, {
        children: [
            hs(DFL.PanelSection, {
                title: "Gleipnir: 80% charge ceiling",
                children: [
                    h(DFL.PanelSectionRow, { children: h(DFL.Field, { label: "State", description: describeState(status) }) }),
                    h(DFL.PanelSectionRow, { children: h(DFL.Field, { label: "Battery", description: describeBattery(d) }) }),
                    status.error && h(DFL.PanelSectionRow, { children: h(DFL.Field, { label: "Problem", description: status.error }) }),
                    !status.installed && h(DFL.PanelSectionRow, {
                        children: h(DFL.ButtonItem, {
                            layout: "below", disabled: busy,
                            onClick: () => act(install, "Installed. It only watches until the test passes."),
                            children: "Install daemon"
                        })
                    }),
                    status.installed && h(DFL.PanelSectionRow, {
                        children: h(DFL.Field, {
                            label: "Sleep type",
                            description: d.sleep_mode === "fake" ? "Fake sleep: Gleipnir keeps running while the Thor sleeps. Change it in Armada Control."
                                : d.sleep_mode === "s2idle" ? "Native sleep: the system freezes Gleipnir, so it clamps just before the sleep (setting below). Change it in Armada Control."
                                : "Unknown (set in Armada Control)"
                        })
                    }),
                    status.installed && d.sleep_mode !== "fake" && h(DFL.PanelSectionRow, {
                        children: h(DFL.DropdownItem, {
                            label: "Charge cap while asleep",
                            description: "Only for native sleep",
                            rgOptions: [
                                { data: 0, label: "Always hold the cap (no charging while asleep)" },
                                { data: 70, label: "Hold from 70% up (charges asleep below that)" },
                                { data: 101, label: "Off (the cap can be passed while asleep)" }
                            ],
                            selectedOption: d.sleep_floor === undefined ? 0 : d.sleep_floor,
                            onChange: (opt) => act(() => setSleepFloor(opt.data)),
                            disabled: busy
                        })
                    }),
                    status.installed && h(DFL.PanelSectionRow, {
                        children: h(DFL.ToggleField, {
                            label: "Enabled",
                            description: "Stopping it puts the charge limit back first",
                            checked: status.active === "active", disabled: busy,
                            onChange: (val) => act(() => setEnabled(val))
                        })
                    })
                ]
            }),
            hs(DFL.PanelSection, {
                title: "Safety test",
                children: [
                    h(DFL.PanelSectionRow, {
                        children: h(DFL.Field, {
                            label: "What it does",
                            description: "Two to four minutes: the limit takes about a minute to act. Needs the charger plugged in and the battery between 10 and 90%. It stops charging briefly, checks that charging really stopped and then resumed, and puts everything back. Gleipnir does nothing until this passes, and it must be re-run after a kernel update."
                        })
                    }),
                    h(DFL.PanelSectionRow, {
                        children: h(DFL.ButtonItem, {
                            layout: "below", disabled: busy || test.running || !plugged,
                            onClick: () => act(startTest),
                            children: test.running ? "Test running..." : (plugged ? "Run test" : "Plug in the charger to test")
                        })
                    }),
                    test.running && h(DFL.PanelSectionRow, {
                        children: h(DFL.ButtonItem, { layout: "below", onClick: () => act(cancelTest), children: "Cancel (restores the limit)" })
                    }),
                    verdictText && h(DFL.PanelSectionRow, { children: h(DFL.Field, { label: "Last result", description: verdictText }) }),
                    test.tail && test.tail.length > 0 && h(DFL.PanelSectionRow, { children: mono(test.tail.slice(-12).join("\n")) })
                ]
            }),
            hs(DFL.PanelSection, {
                title: "Log and maintenance",
                children: [
                    h(DFL.PanelSectionRow, { children: h(DFL.ButtonItem, { layout: "below", onClick: showLog, children: "Show recent log" }) }),
                    log && h(DFL.PanelSectionRow, { children: mono(log.length ? log.join("\n") : "(no log lines yet)") }),
                    h(DFL.PanelSectionRow, {
                        children: h(DFL.ButtonItem, {
                            layout: "below", disabled: busy,
                            onClick: () => act(async () => { const r = await restoreNow(); return r && r.ok ? null : r; }, "Charging limit restored"),
                            children: "Restore normal charging now"
                        })
                    }),
                    status.installed && h(DFL.PanelSectionRow, {
                        children: h(DFL.ButtonItem, {
                            layout: "below", disabled: busy,
                            onClick: () => act(uninstall, "Uninstalled"),
                            children: "Uninstall daemon"
                        })
                    })
                ]
            })
        ]
    });
}

const index = definePlugin((serverApi) => {
    return {
        name: "Gleipnir",
        content: h(Content, {}),
        icon: h("svg", {
            xmlns: "http://www.w3.org/2000/svg",
            viewBox: "0 0 24 24",
            width: "24",
            height: "24",
            fill: "none",
            stroke: "currentColor",
            strokeWidth: "2",
            strokeLinecap: "round",
            strokeLinejoin: "round",
            children: [
                h("rect", { x: "6", y: "7", width: "12", height: "13", rx: "2" }),
                h("path", { d: "M10 4h4M9 13l2 2 4-4" })
            ]
        }),
        onDismount() {}
    };
});

export { index as default };
