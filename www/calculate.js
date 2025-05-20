import { PrintType } from './wasm_to_js.js'
let WasmMemory = null;
let WasmObj = null;
let WasmExports = null;
const TD = new TextDecoder();
const TE = new TextEncoder();
onmessage = onmessage_f;
//Because CalculateProbability might take a while (And freezes the browser page), a Worker and shared wasm memory is used to prevent freezes.
const worker_module = {
    CalculateProbability
};
function SetSubsystemNumber(subsystems) {
    postMessage(['SetSubsystemNumber', subsystems]);
}
function SetTimeoutProgress(subsystem_id, progress) {
    postMessage(['SetTimeoutProgress', subsystem_id, progress]);
}
function CalculateProbability() {
    postMessage(['parse_probability_list', WasmExports.CalculateProbability()]);
}
async function onmessage_f(e) {
    if (e.data[0] == 'f') {
        if (WasmObj != null && WasmExports != null)
            worker_module[e.data[1]](...e.data.slice(2));
        else
            setTimeout(onmessage_f, 1000, e);
    } else if (e.data[0] = 'm') {
        WasmMemory = e.data[1];
        const wasm_obj = await WebAssembly.instantiateStreaming(fetch('./minesweeper_calculator.wasm'), {
            env: { memory: WasmMemory, JSPrint, ClearResults, AppendResults, FinalizeResults, SetSubsystemNumber, SetTimeoutProgress },
        });
        WasmObj = wasm_obj;
        WasmExports = wasm_obj.instance.exports;
    } else {
        console.error('Invalid postMessage flag: ' + e.data[0]);
    }
}
function JSPrint(buffer_addr, expected_len, marked_full) {
    const byte_view = new Uint8Array(WasmMemory.buffer);
    const num_messages = byte_view[buffer_addr];
    let byte_now = buffer_addr + 1;
    let last_print_type = null;
    let combined_str = "";
    for (let i = 0; i < num_messages; i++) {
        const print_type = byte_view[byte_now];
        byte_now += 1;
        if (byte_now - buffer_addr === expected_len) {
            console.error("Corrupted string: Reading byte outside of expected length");
        }
        if (print_type >= PrintType.$$length) {
            console.error("Corrupted string: Invalid PrintType");
        }
        const num_bytes = byte_view[byte_now] | (byte_view[byte_now + 1] << 8);
        byte_now += 2;
        if (byte_now - buffer_addr >= expected_len) {
            console.error("Corrupted string: Reading byte outside of expected length");
        }
        let str = "";
        for (let i = 0; i < num_bytes; i++) {
            str += String.fromCharCode(byte_view[byte_now++]);
            if (byte_now - buffer_addr > expected_len) {
                console.error("Corrupted string: Reading byte outside of expected length");
            }
        }
        if (print_type === last_print_type) {
            combined_str += str;
        } else {
            if (last_print_type != null) postMessage(['do_print', combined_str, last_print_type]);
            combined_str = str;
            last_print_type = print_type;
        }
    }
    if (last_print_type != null) postMessage(['do_print', combined_str, last_print_type]);
    if (marked_full) console.error(`A log message is truncated due to overflowing ${WasmObj.instance.exports.PrintBufferMax()} maximum bytes. Use FlushPrint() to flush the buffer.`);
}
function ClearResults() {
    postMessage(['ClearResults']);
}
function AppendResults(str_ptr, str_len) {
    if (str_len == 0) {
        console.warn('str_len is 0 in AppendResults. str_ptr will not be used.')
        return;
    }
    const string = copy_shared(str_ptr, str_len);
    postMessage(['AppendResults', string]);
}
function FinalizeResults() {
    postMessage(['FinalizeResults']);
}
//Because memory is shared, WasmMemory.buffer (As a SharedArrayBuffer) requires more code to copy for TextDecoder to work.
function copy_shared(addr, len) {
    const buffer_view = new Uint8Array(WasmMemory.buffer, addr, len);
    const copy_ab = new ArrayBuffer(len);
    const copy_ab_view = new Uint8Array(copy_ab);
    copy_ab_view.set(buffer_view, 0);
    return TD.decode(copy_ab_view);
}