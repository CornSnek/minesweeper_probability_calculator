import {
    PrintType, MsType, CalculateArray,
    CalculateStatus, Calculate, ProbabilityList,
    LocationCount, IDToLocationExtern, TileLocation, MineFrequency
} from './wasm_to_js.js'
let WasmObj = null;
let WasmExports = null;
let calculate_worker = null;
const WasmMemory = new WebAssembly.Memory({ initial: 20, maximum: 65536, shared: true });
const TD = new TextDecoder();
const TE = new TextEncoder();
let grid_body = null;
let tiles_palette;
let tile_description;
let tile_gui;
let size_image;
let all_right_tabs;
let columns_num;
let rows_num;
let generate_grid;
let calculate_probability;
let clear_probability_button;
let clear_all_button;
let probability_results_text;
let show_results_check;
let progress_div;
let calculate_progress;
let subsystem_progress;
let flash_body;
let flash_close;
let flash_content;
let get_gm_probability;
let gm_count;
let rows = null;
let columns = null;
let keybind_map = new Map();
let shift_key_down = false;
let ctrl_key_down = false;
let is_calculating = false;
let tile_colors = {};
function do_print(str, print_type) {
    if (print_type === PrintType.log) {
        console.log(str);
    } else if (print_type === PrintType.warn) {
        console.warn(str);
    } else {
        console.error(str);
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
            if (last_print_type != null) do_print(combined_str, last_print_type);
            combined_str = str;
            last_print_type = print_type;
        }
    }
    if (last_print_type != null) do_print(combined_str, last_print_type);
    if (marked_full) console.error(`A log message is truncated due to overflowing ${WasmObj.instance.exports.PrintBufferMax()} maximum bytes. Use FlushPrint() to flush the buffer.`);
}
async function init() {
    if ('serviceWorker' in navigator) {
        try {
            await navigator.serviceWorker.register('./coi-serviceworker.js', { scope: '/minesweeper_probability_calculator/' });
            console.log('COI service worker registered and active');
        } catch (err) {
            console.error('Failed to register COI service worker:', err);
        }
    }
    grid_body = document.getElementById('grid-body');
    tiles_palette = document.getElementById('tiles-palette');
    tile_description = document.getElementById('tile-description');
    tile_gui = document.getElementById('tile-gui');
    all_right_tabs = document.getElementById('all-right-tabs');
    columns_num = document.getElementById('columns-num');
    rows_num = document.getElementById('rows-num');
    generate_grid = document.getElementById('generate-grid');
    calculate_probability = document.getElementById('calculate-probability');
    clear_probability_button = document.getElementById('clear-probability-button');
    clear_all_button = document.getElementById('clear-all-button');
    probability_results_text = document.getElementById('probability-results-text');
    show_results_check = document.getElementById('show-results-check');
    calculate_progress = document.getElementById('calculate-progress');
    subsystem_progress = document.getElementById('subsystem-progress');
    progress_div = document.getElementById('progress-div');
    flash_body = document.getElementById('flash-body');
    flash_close = document.getElementById('flash-close');
    flash_content = document.getElementById('flash-content');
    get_gm_probability = document.getElementById('get-gm-probability');
    gm_count = document.getElementById('gm-count');
    const root_comp = getComputedStyle(document.documentElement);
    size_image = size_image = parseFloat(root_comp.getPropertyValue('--size-image').trim());
    tile_colors.neutral = root_comp.getPropertyValue('--ms-probability');
    tile_colors.mine = root_comp.getPropertyValue('--ms-probability-mine');
    tile_colors.clear = root_comp.getPropertyValue('--ms-probability-clear');
    for (const tile_name of MsType.$$names) {
        const ms_type = MsType[tile_name];
        if (MsType.$in_palette[ms_type]) {
            const container_div = document.createElement('div');
            tiles_palette.appendChild(container_div);
            container_div.classList.add('tile-palette-container');
            const image_div = document.createElement('div');
            container_div.appendChild(image_div);
            image_div.classList.add('tile');
            image_div.dataset.ms_type = ms_type;
            image_div.onclick = assign_selected_f.bind({ tile: MsType[tile_name], selected_tile });
            image_div.onmouseenter = () => {
                image_div.classList.add('tile-hovered');
                tile_description.textContent = MsType.$description[MsType[tile_name]];
            };
            image_div.onmouseleave = () => {
                image_div.classList.remove('tile-hovered');
                tile_description.textContent = get_default_tile_description();
            };
            update_tile_div(image_div, false); //Don't show as clicked.
            const keybind_div = document.createElement('div');
            container_div.appendChild(keybind_div);
            keybind_div.innerHTML = `<strong class="badge">${MsType.$js_ch[ms_type].toUpperCase()}</strong>`;
        }
    }
    const wasm_obj = await WebAssembly.instantiateStreaming(fetch('./minesweeper_calculator.wasm'), {
        env: { memory: WasmMemory, JSPrint, ClearResults, AppendResults, FinalizeResults, SetSubsystemNumber, SetTimeoutProgress },
    });
    WasmObj = wasm_obj;
    WasmExports = wasm_obj.instance.exports;
    init_grid(parseInt(columns_num.value), parseInt(rows_num.value));
    document.addEventListener('keydown', e => {
        if (!e.repeat) {
            if (e.key == 'Shift') {
                shift_key_down = true;
            } else if (e.key == 'Control') {
                ctrl_key_down = true;
            } else {
                if (ctrl_key_down) {
                    switch (e.key) {
                        case 'c':
                            selected_tile.copy_text_clipboard(false);
                            break;
                        case 'x':
                            selected_tile.copy_text_clipboard(true);
                    }
                } else {
                    const fn = keybind_map.get(e.key);
                    if (fn !== undefined) fn(e);
                }
            }
        }
    });
    document.addEventListener('keyup', e => {
        if (e.key == 'Shift') {
            shift_key_down = false;
        } else if (e.key == 'Control') {
            ctrl_key_down = false;
        }
    });
    document.querySelectorAll('.close-options-panel').forEach(link => link.onclick = hide_any_right_panels);
    [...all_right_tabs.children].forEach(tab_elem => {
        const tab_id = tab_elem.dataset.tab;
        if (tab_id !== undefined) {
            tab_elem.onclick = (e) => show_tab(tab_elem, tab_id);
        }
    });
    rows_num.onchange = e => rows_num.value = Math.min(Math.max(parseInt(rows_num.value), 1), 100);
    columns_num.onchange = e => columns_num.value = Math.min(Math.max(parseInt(columns_num.value), 1), 100);
    gm_count.onchange = e => gm_count.value = Math.max(parseInt(gm_count.value), 0);
    generate_grid.onclick = e => {
        if (is_calculating) return;
        if (confirm('Are you sure? This will clear all tiles.')) {
            init_grid(parseInt(columns_num.value), parseInt(rows_num.value));
        }
    };
    calculate_probability.onclick = e => {
        if (!is_calculating) {
            hide_flash();
            start_progress();
            deselect_tiles_f();
            calculate_worker.postMessage(['f', 'CalculateProbability']);
            SetTimeoutProgress(0, 0.0);
            calculate_probability.textContent = 'Cancel Calculation';
        } else {
            Atomics.store(new Uint8Array(WasmMemory.buffer), WasmExports.CancelCalculation.value, 1);
            flash_message(FLASH_ERROR, 'Cancelled Calculation');
        }
    };
    clear_probability_button.onclick = clear_all_probability;
    clear_all_button.onclick = e => {
        if (is_calculating) return;
        if (confirm('Are you sure? This will clear all tiles.'))
            init_grid(parseInt(columns_num.value), parseInt(rows_num.value))
    };
    document.addEventListener('paste', e => selected_tile.paste_text_clipboard(e.clipboardData.getData('text')));
    document.body.style.marginRight = `${all_right_tabs.offsetWidth}px`;
    document.body.style.marginBottom = `${tile_gui.offsetHeight}px`;
    calculate_worker = new Worker("./calculate.js", { type: 'module' });
    calculate_worker.onerror = end_progress;
    calculate_worker.onmessage = e => {
        worker_handler_module[e.data[0]](...e.data.slice(1));
    };
    calculate_worker.postMessage(['m', WasmMemory]);
    document.querySelectorAll('#patterns-body .tile-template').forEach(div => {
        create_board_pattern(div, div.dataset.ncolumns, div.dataset.str);
        div.onclick = e => {
            const copy_data = SelectedTile.ClipboardHeader + div.dataset.str.replace(/[cv][.?]/g, 'c');
            navigator.clipboard.writeText(copy_data).catch(err => console.warn('Clipboard copy failed: ' + err));
            flash_message(FLASH_SUCCESS, 'Copied to Clipboard');
        };
    });
    flash_close.onclick = hide_flash;
    console.log('Waiting for KaTeX module...');
    wait_katex();
}
const FLASH_ERROR = 0;
const FLASH_SUCCESS = 1;
function flash_message(type, message) {
    flash_body.style.display = 'inline-flex';
    flash_content.textContent = message;
    if (type === FLASH_SUCCESS) {
        flash_body.classList.add('flash-success');
        flash_body.classList.remove('flash-error');
    } else if (type === FLASH_ERROR) {
        flash_body.classList.add('flash-error');
        flash_body.classList.remove('flash-success');
    } else {
        console.err('Invalid flash_message type');
    }
}
function hide_flash() {
    flash_body.style.display = 'none';
}
const worker_handler_module = {
    JSPrint,
    ClearResults,
    AppendResults,
    FinalizeResults,
    SetSubsystemNumber,
    SetTimeoutProgress,
    parse_probability_list,
    do_print,
};
function show_tab(tab_elem, tab_id) {
    deselect_tiles_f();
    hide_any_right_panels();
    const tab = document.getElementById(tab_id);
    tab.classList.add('panel-show');
    tab.classList.remove('panel-hide-right');
    all_right_tabs.classList.add('right-tabs-expand');
    all_right_tabs.classList.remove('right-tabs-normal');
    document.querySelector(':root').style.setProperty('--all-tabs-shift', `-${tab.offsetWidth}px`);
    tab_elem.classList.add('tab-selected');
    document.body.style.marginRight = `${all_right_tabs.offsetWidth + tab.offsetWidth}px`;
}
function wait_katex() {
    if (window.katex && window.katex.render) {
        console.log('KaTeX module is loaded');
        return;
    }
    setTimeout(() => wait_katex(), 500);
}
function hide_any_right_panels(e) {
    if (e !== undefined) e.preventDefault();
    document.body.style.marginRight = `${all_right_tabs.offsetWidth}px`;
    const shown_panel = document.querySelector('#all-options-gui .panel-show');
    if (shown_panel !== null) {
        shown_panel.classList.remove('panel-show');
        shown_panel.classList.add('panel-hide-right');
        all_right_tabs.classList.remove('right-tabs-expand');
        all_right_tabs.classList.add('right-tabs-normal');
    }
    const selected_tab = document.querySelector('#all-right-tabs .tab-selected');
    if (selected_tab !== null) {
        selected_tab.classList.remove('tab-selected');
    }
}
document.addEventListener('DOMContentLoaded', init);
function init_grid(num_columns, num_rows) {
    console.assert(num_columns > 0 && num_rows > 0, 'num_columns and num_rows should be greater than 0');
    rows = num_rows;
    columns = num_columns;
    WasmExports.CreateGrid(num_columns, num_rows);
    document.querySelector(':root').style.setProperty('--num-columns', num_columns);
    grid_body.textContent = '';
    for (let i = 0; i < num_columns * num_rows; i++) {
        const x = i % num_columns;
        const y = Math.floor(i / num_columns);
        const div = document.createElement('div');
        grid_body.appendChild(div);
        div.classList.add('tile');
        div.dataset.x = x;
        div.dataset.y = y;
        div.dataset.ms_type = MsType.unknown;
        div.onclick = e => {
            if (is_calculating) return;
            tile_select_f.bind(new SelectedTile({
                t: SelectedTile.One, p: new TilePoint(div.dataset.x, div.dataset.y)
            }))(e);
        };
        div.onmouseenter = () => div.classList.add('tile-hovered');
        div.onmouseleave = () => div.classList.remove('tile-hovered');
    }
    for (const div of grid_body.children) update_tile_div(div, true);
}
class TilePoint {
    constructor(x, y) {
        this.x = x;
        this.y = y;
    }
}
function regex_escape(str) {
    return str.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}
class SelectedTile {
    static None = 0;
    static One = 1;
    static Many = 2;
    static Down = 0;
    static Up = 1;
    static Left = 2;
    static Right = 3;
    static ClipboardHeader = 'ms-clipboard-data:';
    static ClipboardHeaderRegex = new RegExp(`^${regex_escape(SelectedTile.ClipboardHeader)}\\s*`);
    constructor(options) {
        if (options === undefined) {
            this.select_none();
        } else {
            switch (options.t) {
                case SelectedTile.One:
                    this.select_one(parseInt(options.p.x), parseInt(options.p.y));
                    break;
                case SelectedTile.Many:
                    this.select_many(parseInt(options.p.x), parseInt(options.p.y),
                        parseInt(options.s.x), parseInt(options.s.y)
                    );
                    break;
                default:
                    this.select_none();
            }
        }
    }
    select_none() {
        this.type = SelectedTile.None;
        this.select = undefined;
    }
    select_one(x, y) {
        this.type = SelectedTile.One;
        this.select = new TilePoint(x, y);
    }
    select_many(x, y, w, h) {
        this.type = SelectedTile.Many;
        this.select = { p: new TilePoint(x, y), s: new TilePoint(w, h) };
    }
    shift(shift_enum) {
        console.assert(rows != null && columns != null, 'rows and columns must not be null');
        switch (this.type) {
            case SelectedTile.One:
                switch (shift_enum) {
                    case SelectedTile.Down:
                        if (this.select.y + 1 < rows) {
                            this.select.y += 1;
                        }
                        break;
                    case SelectedTile.Up:
                        if (this.select.y >= 1) {
                            this.select.y -= 1;
                        }
                        break;
                    case SelectedTile.Left:
                        if (this.select.x >= 1) {
                            this.select.x -= 1;
                        }
                        break;
                    case SelectedTile.Right:
                        if (this.select.x + 1 < columns) {
                            this.select.x += 1;
                        }
                }
                break;
            case SelectedTile.Many:
                switch (shift_enum) {
                    case SelectedTile.Down:
                        //Lowermost boundary is p.y + s.y - 1. Then add + 1 to check the next tile.
                        if (this.select.p.y + this.select.s.y < rows) {
                            this.select.p.y += 1;
                        }
                        break;
                    case SelectedTile.Up:
                        if (this.select.p.y >= 1) {
                            this.select.p.y -= 1;
                        }
                        break;
                    case SelectedTile.Left:
                        if (this.select.p.x >= 1) {
                            this.select.p.x -= 1;
                        }
                        break;
                    case SelectedTile.Right:
                        //Rightmost boundary is p.x + s.x - 1. Then add + 1 to check the next tile.
                        if (this.select.p.x + this.select.s.x < columns) {
                            this.select.p.x += 1;
                        }
                        break;
                }
                break;
        }
    }
    get_div_array() {
        console.assert(grid_body != null && columns != null, 'grid_body and columns must not be null');
        const array = [];
        switch (this.type) {
            case SelectedTile.One:
                array.push(grid_body.children[this.select.y * columns + this.select.x]);
                break;
            case SelectedTile.Many:
                for (let j = this.select.p.y; j < this.select.p.y + this.select.s.y; j++) {
                    for (let i = this.select.p.x; i < this.select.p.x + this.select.s.x; i++) {
                        array.push(grid_body.children[j * columns + i]);
                    }
                }
        }
        return array;
    }
    move(new_st) {
        this.type = new_st.type;
        this.select = new_st.select;
    }
    copy_text_clipboard(clear_data) {
        console.assert(grid_body != null, 'grid_body must not be null');
        let copy_data = SelectedTile.ClipboardHeader;
        if (this.type == SelectedTile.One) {
            const div = grid_body.children[this.select.y * columns + this.select.x];
            copy_data += MsType.$js_ch[div.dataset.ms_type] + ',';
        } else if (this.type == SelectedTile.Many) {
            for (let j = this.select.p.y; j < this.select.p.y + this.select.s.y; j++) {
                for (let i = this.select.p.x; i < this.select.p.x + this.select.s.x; i++) {
                    const div = grid_body.children[j * columns + i];
                    copy_data += MsType.$js_ch[div.dataset.ms_type];
                    if (clear_data)
                        assign_selected_f.bind({
                            tile: MsType.unknown, selected_tile: new SelectedTile({
                                t: SelectedTile.One, p: new TilePoint(i, j)
                            })
                        })();
                }
                copy_data += ',';
            }
        }
        navigator.clipboard.writeText(copy_data).catch(err => console.warn('Clipboard copy failed: ' + err));
    }
    paste_text_clipboard(pasted_text) {
        console.assert(grid_body != null || rows != null || columns != null, 'grid_body/rows/columns must not be null');
        if (this.type == SelectedTile.None) return;
        if (pasted_text.startsWith(SelectedTile.ClipboardHeader)) {
            pasted_text = pasted_text.replace(SelectedTile.ClipboardHeaderRegex, '');
            let tp;
            let tp_end;
            if (this.type == SelectedTile.One) {
                tp = new TilePoint(this.select.x, this.select.y);
                tp_end = new TilePoint(this.select.x, this.select.y);
            } else if (this.type == SelectedTile.Many) {
                tp = new TilePoint(this.select.p.x, this.select.p.y);
                tp_end = new TilePoint(this.select.p.x, this.select.p.y);
            }
            let tp_old_x = tp.x;
            let tp_old_y = tp.y;
            for (let ch_i = 0; ch_i < pasted_text.length; ch_i++) {
                let tile_enum;
                if ((tile_enum = ch_to_tile_enum.get(pasted_text[ch_i])) !== undefined) {
                    if (tp.x < columns && tp.y < rows) {
                        assign_selected_f.bind({
                            tile: tile_enum, selected_tile: new SelectedTile({
                                t: SelectedTile.One, p: new TilePoint(tp.x, tp.y)
                            })
                        })();
                        tp_end = new TilePoint(tp.x, tp.y);
                    }
                }
                if (pasted_text[ch_i] === ',') {
                    tp.y += 1;
                    tp.x = tp_old_x;
                } else tp.x += 1;
            }
            //Show select region after pasting
            if (tp_old_x == tp_end.x && tp_old_y == tp_end.y) {
                tile_select_f.bind(new SelectedTile({
                    t: SelectedTile.One, p: new TilePoint(tp_old_x, tp_old_y)
                }))();
            } else {
                tile_select_f.bind(new SelectedTile({
                    t: SelectedTile.Many, p: new TilePoint(tp_old_x, tp_old_y), s: new TilePoint(tp_end.x - tp_old_x + 1, tp_end.y - tp_old_y + 1)
                }))();
            }
        }
    }
}
const selected_tile = new SelectedTile();
const ch_to_tile_enum = new Map();
MsType.$js_ch.forEach((ch, i) => ch_to_tile_enum.set(ch, i));
//Call tile_select_f depending on shift key and already selecting one tile
//to select more than one tile.
function tile_select_f(e) {
    hide_flash();
    console.assert(this instanceof SelectedTile, "The this instance should be SelectedTile");
    if (selected_tile.type != SelectedTile.None && shift_key_down) {
        //Get region based on the top left corner and the clicked tile (this)
        const points_array = [new TilePoint(this.select.x, this.select.y)];
        switch (selected_tile.type) {
            case SelectedTile.One:
                points_array.push(new TilePoint(selected_tile.select.x, selected_tile.select.y));
                break;
            case SelectedTile.Many:
                points_array.push(new TilePoint(selected_tile.select.p.x, selected_tile.select.p.y));
        }
        let min_x = Math.min(points_array[0].x, points_array[1].x);
        let min_y = Math.min(points_array[0].y, points_array[1].y);
        let max_x = Math.max(points_array[0].x, points_array[1].x);
        let max_y = Math.max(points_array[0].y, points_array[1].y);
        const size_p = new TilePoint(max_x - min_x + 1, max_y - min_y + 1);
        tile_select_any_f.bind(new SelectedTile({
            t: SelectedTile.Many, p: new TilePoint(min_x, min_y), s: size_p
        }))(e);
    } else {
        tile_select_any_f.bind(this)(e);
    }
}
function tile_select_any_f(e) {
    if (selected_tile.type !== SelectedTile.None) deselect_tiles_f(e);
    hide_any_right_panels();
    selected_tile.move(this);
    for (const div of selected_tile.get_div_array()) {
        div.classList.add('tile-selected');
    }
    tile_gui.classList.remove('panel-hide-down');
    tile_gui.classList.add('panel-show');
    tile_description.textContent = get_default_tile_description();
    keybind_map.set('Escape', deselect_tiles_f);
    const down_f = e => {
        deselect_tiles_f(e);
        this.shift(SelectedTile.Down);
        tile_select_any_f.bind(this)(e);
    };
    const up_f = e => {
        deselect_tiles_f(e);
        this.shift(SelectedTile.Up);
        tile_select_any_f.bind(this)(e);
    };
    const left_f = e => {
        deselect_tiles_f(e);
        this.shift(SelectedTile.Left);
        tile_select_any_f.bind(this)(e);
    };
    const right_f = e => {
        deselect_tiles_f(e);
        this.shift(SelectedTile.Right);
        tile_select_any_f.bind(this)(e);
    };
    keybind_map.set('ArrowDown', down_f);
    keybind_map.set('s', down_f);
    keybind_map.set('ArrowUp', up_f);
    keybind_map.set('w', up_f);
    keybind_map.set('ArrowLeft', left_f);
    keybind_map.set('a', left_f);
    keybind_map.set('ArrowRight', right_f);
    keybind_map.set('d', right_f);
    for (const [ch, tile] of ch_to_tile_enum) {
        console.assert(keybind_map.get(ch) === undefined, `Warning: Overwriting keybind_map function '${ch}'`);
        keybind_map.set(ch, assign_selected_f.bind({ tile: tile, selected_tile }));
    }
    keybind_map.set('Delete', assign_selected_f.bind({ tile: MsType.unknown, selected_tile }));
}
function assign_selected_f() {
    for (const div of this.selected_tile.get_div_array()) {
        set_tile(parseInt(div.dataset.x), parseInt(div.dataset.y), this.tile);
    }
}
function deselect_tiles_f(e) {
    tile_gui.classList.remove('panel-show');
    tile_gui.classList.add('panel-hide-down')
    for (const div of selected_tile.get_div_array()) {
        div.classList.remove('tile-selected');
    }
    selected_tile.select_none();
    keybind_map.clear();
}
function update_tile_div(div, use_is_clicked) {
    const ms_type = div.dataset.ms_type;
    if (use_is_clicked) {
        if (MsType.$is_clicked[ms_type]) {
            div.classList.add('tile-clicked');
            if (ms_type == MsType.mine)
                div.classList.add('tile-mine');
        } else {
            div.classList.remove('tile-clicked');
            div.classList.remove('tile-mine');
        }
    }
    console.assert(div.dataset.ms_type < MsType.$$length, 'ms_type enum is out of range');
    const image_url = MsType.$image_url[ms_type];
    div.textContent = '';
    const img = document.createElement('img');
    img.src = 'images/' + image_url;
    img.width = size_image;
    img.height = size_image;
    div.appendChild(img);
}
function set_tile(x, y, ms_type) {
    WasmExports.SetTile(x, y, ms_type);
    update_tile(x, y);
}
function update_tile(x, y) {
    console.assert(columns !== null, 'columns have not been set yet');
    const i = y * columns + x;
    const div = grid_body.children[i];
    clear_probability(div);
    const ms_type = WasmExports.QueryTile(x, y);
    div.dataset.ms_type = ms_type;
    update_tile_div(div, true);
}
function clear_all_probability() {
    document.querySelectorAll('[data-probability]').forEach(clear_probability);
}
function clear_probability(div) {
    div.textContent = '';
    div.classList.remove('tile-pb-mine');
    div.classList.remove('tile-pb-clear');
    div.classList.remove('tile-pb-error');
    div.classList.remove('tile-pb-color');
    div.style.removeProperty('--tile-color');
    delete div.dataset.probability;
    delete div.dataset.error;
}
function get_default_tile_description() {
    console.assert(grid_body != null && columns != null, 'grid_body and columns must not be null');
    if (selected_tile.type == SelectedTile.One) {
        const div = grid_body.children[selected_tile.select.y * columns + selected_tile.select.x];
        let status;
        if ((status = div.dataset.error) !== undefined) return CalculateStatus.$error_message[status];
    }
    return '';
}
class MineFrequencyGraph {
    constructor(subsystem) {
        this.subsystem = subsystem;
        this.id = null; //null means the global mine frequency.
        this.map = new Map();
    }
    assign_id(id, x, y) {
        this.id = id;
        this.x = x;
        this.y = y;
    }
    assign_mf(m, f) {
        this.map.set(m, BigInt(f));
    }
    convolve(other_map /*: MineFrequencyGraph*/) {
        const new_map = new Map();
        for (const [sm, sf] of this.map) {
            for (const [om, of] of other_map) {
                const nm = sm + om;
                const nf = sf * of;
                const old_nf = new_map.get(nm) || BigInt(0);
                new_map.set(nm, old_nf + nf);
            }
        }
        this.map = new_map;
    }
}
function format_percentage(bnn, bnd) {
    const per = (Number(bnn) / Number(bnd)) * 100;
    if (bnn === bnd) return per.toFixed();
    else if (per >= 10) return per.toFixed(1);
    else return per.toFixed(2);
}
class MFGList {
    constructor(len) {
        this.global = new Array(len).fill(null); //Null represents if there is an error in a subsystem.
        this.local = new Array(len).fill().map(() => new Array());
    }
    set_global(subsystem, mfg) {
        this.global[subsystem] = mfg;
    }
    add_local(subsystem, mfg) {
        this.local[subsystem].push(mfg);
    }
    convolve_all() {
        const global_mult = new Array();
        for (let i = 0; i < this.global.length; i++) {
            if (this.global[i] === null) return false; //All subsystems must be valid
            global_mult.push(new Map(this.global[i].map)); //Shallow clone when colvolving all MFGs
        }
        for (let i = 0; i < this.global.length; i++) {
            for (let j = 0; j < global_mult.length; j++) { //Convolute each global/local MFG with other global MFG subsystems.
                if (i == j) continue;
                this.global[i].convolve(global_mult[j]);
                this.local[i].forEach(mfg => mfg.convolve(global_mult[j]));
            }
        }
        return true;
    }
    output_probability() {
        let gmfg = null;
        if (this.global.length !== 0) gmfg = this.global[0].map;
        let global_mine_count = parseInt(gm_count.value);
        let mine_flag_count = 0;
        let adjacent_tiles = 0;
        this.local.forEach(mfg_arr => adjacent_tiles += mfg_arr.length);
        let non_adjacent_tiles = 0;
        [...grid_body.children].forEach(div => {
            const ms_type = div.dataset.ms_type;
            non_adjacent_tiles += ms_type == MsType.unknown;
            const is_mine_or_flag = ms_type == MsType.mine || ms_type == MsType.flag;
            global_mine_count -= is_mine_or_flag;
            mine_flag_count += is_mine_or_flag;
        });
        if (global_mine_count <= 0) {
            flash_message(FLASH_ERROR, `Error: Too many flags or mines have been placed! The global mine count (${global_mine_count + mine_flag_count}) is less than the mines + flags placed (${mine_flag_count}).`);
            return;
        }
        non_adjacent_tiles -= adjacent_tiles;
        //console.log(`AT: ${adjacent_tiles}, NAT: ${non_adjacent_tiles}`);
        let a_denominator = 0n;
        let na_denominator = 0n;
        let na_numerator = 0n;
        let max_gm = 0;
        if (gmfg !== null) {
            for (const [gm, gf] of gmfg) {
                if (gm > global_mine_count) {
                    flash_message(FLASH_ERROR, `Error: Too little mines! The global mine count is ${global_mine_count + mine_flag_count} - (${mine_flag_count} mines + flags) = ${global_mine_count}. More than one solution requires using ${gm} or more mines.`);
                    return;
                }
                a_denominator += gf * comb(non_adjacent_tiles, global_mine_count - gm);
                na_numerator += comb(non_adjacent_tiles, global_mine_count - gm) * BigInt(global_mine_count - gm) / BigInt(non_adjacent_tiles);
                na_denominator += comb(non_adjacent_tiles, global_mine_count - gm);
                max_gm = Math.max(max_gm, gm);
            }
            if (a_denominator === 0n) {
                flash_message(FLASH_ERROR, `Error: Too many mines! The global mine count is ${global_mine_count + mine_flag_count} - (${mine_flag_count} mines + flags) = ${global_mine_count}. One solution has a maximum of ${max_gm} mines and there are ${non_adjacent_tiles} non-adjacent tiles to fill, resulting in the sum of only ${max_gm + non_adjacent_tiles} mines.`);
                return;
            }
        }
        this.local.forEach(mfg_arr => {
            mfg_arr.forEach(mfg => {
                let a_numerator = 0n;
                for (const [gm, gf] of mfg.map) a_numerator += gf * comb(non_adjacent_tiles, global_mine_count - gm);
                const pb = format_percentage(a_numerator, a_denominator);
                const x = mfg.x;
                const y = mfg.y;
                const div = grid_body.children[y * columns + x];
                div.textContent = `\\( \\htmlStyle{font-size: 0.75em}{${pb}\\\%} \\)`;
                renderMathInElement(div,{
                    trust: true,
                    strict: (code) => code === "htmlExtension" ? "ignore" : "warn",
                });
                if (a_numerator == a_denominator)
                    div.classList.add('tile-pb-mine');
                else if (a_numerator == 0n)
                    div.classList.add('tile-pb-clear');
                else {
                    div.classList.add('tile-pb-color');
                    const percentage = Number(a_numerator) / Number(a_denominator);
                    let tc;
                    if (percentage <= 0.5)
                        tc = color_lerp(tile_colors.clear, tile_colors.neutral, percentage * 2);
                    else
                        tc = color_lerp(tile_colors.neutral, tile_colors.mine, percentage * 2 - 1);
                    div.style.setProperty('--tile-color', tc);
                }
                div.dataset.probability = 'y';
            });
        });
        //Probability of an empty matrix (All unknowns) is just (number of mines)/(number of non-adjacent tiles)
        if (this.global.length === 0) {
            na_denominator = non_adjacent_tiles;
            na_numerator = global_mine_count;
        }
        //console.log(na_numerator, na_denominator, (100 * Number(na_numerator) / Number(na_denominator)).toFixed(2));
        [...grid_body.children].forEach(div => { //Fill Non-adjacent unknown tiles with the same probability
            if (div.dataset.ms_type == MsType.unknown && div.dataset.probability === undefined) {
                const pb = format_percentage(na_numerator, na_denominator);
                div.textContent = `\\( \\htmlStyle{font-size: 0.75em}{${pb}\\\%} \\)`;
                renderMathInElement(div,{
                    trust: true,
                    strict: (code) => code === "htmlExtension" ? "ignore" : "warn",
                });
                if (na_numerator == na_denominator)
                    div.classList.add('tile-pb-mine');
                else if (na_numerator == 0n)
                    div.classList.add('tile-pb-clear');
                else {
                    div.classList.add('tile-pb-color');
                    const percentage = Number(na_numerator) / Number(na_denominator);
                    let tc;
                    if (percentage <= 0.5)
                        tc = color_lerp(tile_colors.clear, tile_colors.neutral, percentage * 2);
                    else
                        tc = color_lerp(tile_colors.neutral, tile_colors.mine, percentage * 2 - 1);
                    div.style.setProperty('--tile-color', tc);
                }
                div.dataset.probability = 'y';
            }
        });
    }
}
function comb(n, r) {
    if (r < 0 || r > n) return 0n;
    if (r === 0 || r === n) return 1n;
    let res = 1n;
    const nbig = BigInt(n);
    const rbig = BigInt(r);
    for (let i = 1n; i <= rbig; i++) {
        res *= nbig - (rbig - i);
        res /= i;
    }
    return res;
}
let mfg_list = new MFGList(0);
function parse_probability_list(c_arr_ptr) {
    end_progress();
    deselect_tiles_f();
    clear_all_probability();
    if (show_results_check.checked) {
        const results_tab_button = document.getElementById('results-tab-button');
        show_tab(results_tab_button, 'results-tab');
    }
    const calc_arr = new DataView(WasmMemory.buffer, c_arr_ptr, CalculateArray.$size);
    const calc_arr_status = calc_arr.getUint8(CalculateArray.status.offset, true);
    if (calc_arr_status == CalculateStatus.ok) {
        const ca_ptr = calc_arr.getUint32(CalculateArray.ptr.offset, true);
        const ca_len = calc_arr.getUint32(CalculateArray.len.offset, true);
        mfg_list = new MFGList(ca_len);
        let ca;
        //ca_ptr is 'undefined' in zig when ca_len is 0.
        if (ca_len !== 0) ca = new DataView(WasmMemory.buffer, ca_ptr, Calculate.$size * ca_len);
        for (let ca_i = 0; ca_i < ca_len; ca_i++) {
            const calc_status = ca.getUint8(ca_i * Calculate.$size + Calculate.status.offset, true);
            const calc_ptr = ca_ptr + ca_i * Calculate.$size;
            if (calc_status == CalculateStatus.ok) {
                const pl = new DataView(WasmMemory.buffer, calc_ptr + Calculate.pl.offset, ProbabilityList.$size);
                const total_solutions = pl.getUint32(ProbabilityList.total.offset, true);
                const lc_ptr = pl.getUint32(ProbabilityList.lc_ptr.offset, true);
                const lc_len = pl.getUint32(ProbabilityList.lc_len.offset, true);
                const lc = new DataView(WasmMemory.buffer, lc_ptr, lc_len * LocationCount.$size);
                for (let lc_i = 0; lc_i < lc_len; lc_i++) {
                    const x = lc.getUint32(lc_i * LocationCount.$size + LocationCount.x.offset, true);
                    const y = lc.getUint32(lc_i * LocationCount.$size + LocationCount.y.offset, true);
                    const count = lc.getUint32(lc_i * LocationCount.$size + LocationCount.count.offset, true);
                    const mf_len = lc.getUint32(lc_i * LocationCount.$size + LocationCount.mf_len.offset, true);
                    const mfg = new MineFrequencyGraph(ca_i);
                    mfg.assign_id(lc_i, x, y);
                    if (mf_len != 0) {
                        const mf_ptr = lc.getUint32(lc_i * LocationCount.$size + LocationCount.mf_ptr.offset, true);
                        const mf = new DataView(WasmMemory.buffer, mf_ptr, mf_len * MineFrequency.$size);
                        for (let mf_i = 0; mf_i < mf_len; mf_i++) {
                            const m = mf.getUint32(mf_i * MineFrequency.$size + MineFrequency.m.offset, true);
                            const f = mf.getUint32(mf_i * MineFrequency.$size + MineFrequency.f.offset, true);
                            mfg.assign_mf(m, f);
                        }
                    }
                    mfg_list.add_local(ca_i, mfg);
                    if (!get_gm_probability.checked) {
                        const div = grid_body.children[y * columns + x];
                        div.textContent = `\\( \\frac{${count}}{${total_solutions}} \\)`;
                        renderMathInElement(div);
                        if (count == total_solutions)
                            div.classList.add('tile-pb-mine');
                        else if (count == 0)
                            div.classList.add('tile-pb-clear');
                        else {
                            div.classList.add('tile-pb-color');
                            const percentage = count / total_solutions;
                            let tc;
                            if (percentage <= 0.5)
                                tc = color_lerp(tile_colors.clear, tile_colors.neutral, percentage * 2);
                            else
                                tc = color_lerp(tile_colors.neutral, tile_colors.mine, percentage * 2 - 1);
                            div.style.setProperty('--tile-color', tc);
                        }
                        div.dataset.probability = 'y';
                    }
                }
                const mf_ptr = pl.getUint32(ProbabilityList.mf_ptr.offset, true);
                const mf_len = pl.getUint32(ProbabilityList.mf_len.offset, true);
                const mf = new DataView(WasmMemory.buffer, mf_ptr, mf_len * MineFrequency.$size);
                const mfg_global = new MineFrequencyGraph(ca_i);
                for (let mf_i = 0; mf_i < mf_len; mf_i++) {
                    const m = mf.getUint32(mf_i * MineFrequency.$size + MineFrequency.m.offset, true);
                    const f = mf.getUint32(mf_i * MineFrequency.$size + MineFrequency.f.offset, true);
                    mfg_global.assign_mf(m, f);
                }
                mfg_list.set_global(ca_i, mfg_global);
            } else {
                const tm = new DataView(WasmMemory.buffer, calc_ptr + Calculate.tm.offset, IDToLocationExtern.$size);
                const tl_ptr = tm.getUint32(IDToLocationExtern.ptr.offset, true);
                const tl_len = tm.getUint32(IDToLocationExtern.len.offset, true);
                const tl_arr = new DataView(WasmMemory.buffer, tl_ptr, TileLocation.$size * tl_len);
                for (let tl_i = 0; tl_i < tl_len; tl_i++) {
                    const x = tl_arr.getUint32(tl_i * TileLocation.$size + TileLocation.x.offset, true);
                    const y = tl_arr.getUint32(tl_i * TileLocation.$size + TileLocation.y.offset, true);
                    const div = grid_body.children[y * columns + x];
                    div.textContent = 'Err!';
                    div.classList.add('tile-pb-error');
                    div.dataset.probability = 'y';
                    div.dataset.error = calc_status;
                }
            }
        }
        if (get_gm_probability.checked && mfg_list.convolve_all()) mfg_list.output_probability();
    } else {
        flash_message(FLASH_ERROR, 'Encountered an error: \'' + CalculateStatus.$error_message[calc_arr_status]) + '\'';
    }
}
function ClearResults() {
    probability_results_text.innerHTML = 'Probability Results<br><br>';
}
function AppendResults(string) {
    probability_results_text.innerHTML += string;
}
function FinalizeResults() {
    renderMathInElement(probability_results_text);
}
let debounce_timeout = false;
function start_progress() {
    is_calculating = true;
    progress_div.style.display = 'initial';
}
function SetSubsystemNumber(subsystems) {
    subsystem_progress.max = subsystems;
}
function SetTimeoutProgress(subsystem_id, progress) {
    if (debounce_timeout) return;
    debounce_timeout = true;
    setTimeout(() => {
        Atomics.store(new Uint8Array(WasmMemory.buffer), WasmExports.CalculateStatus.value, 1);
        debounce_timeout = false;
        renderMathInElement(probability_results_text);
    }, 1000);
    subsystem_progress.value = subsystem_id + 1;
    calculate_progress.value = progress;
}
function end_progress() {
    is_calculating = false;
    calculate_progress.value = 1;
    progress_div.style.display = 'none';
    calculate_probability.textContent = 'Calculate Probability';
}
function create_board_pattern(div_parent, num_columns, tile_string) {
    div_parent.classList.add('tile-template');
    div_parent.style.setProperty('--num-columns', num_columns);
    for (let ch_i = 0; ch_i < tile_string.length; ch_i++) {
        const this_ch = tile_string[ch_i];
        const next_ch = (ch_i != tile_string.length) ? tile_string[ch_i + 1] : null;
        let tile_enum;
        if ((tile_enum = ch_to_tile_enum.get(this_ch)) !== undefined) {
            const tile_div = document.createElement('div');
            div_parent.appendChild(tile_div);
            tile_div.classList.add('tile');
            tile_div.dataset.ms_type = tile_enum;
            update_tile_div(tile_div, true);
            if (next_ch == '.') {
                if (tile_enum == MsType.unknown) {
                    tile_div.classList.add('tile-pb-clear');
                    tile_div.textContent = '';
                } else if (tile_enum == MsType.mine) {
                    tile_div.classList.add('tile-pb-mine');
                    tile_div.textContent = '';
                } else {
                    console.error(`Character '${this_ch}' is only used for unknowns or mines for string '${tile_string}' at index #${ch_i}`);
                }
                ch_i++;
            } else if (next_ch == '?') {
                if (tile_enum == MsType.unknown) {
                    tile_div.classList.add('tile-pb-q');
                    tile_div.textContent = '';
                } else {
                    console.error(`Character '${this_ch}' is only used for unknowns for string '${tile_string}' at index #${ch_i}`);
                }
                ch_i++;
            }
        } else if (this_ch != ',') {
            console.error(`Character '${this_ch}' is not part of the tile set for string '${tile_string}' at index #${ch_i}`);
        }
    }
}
function color_lerp(color1, color2, percent) {
    function parse_hex(color) {
        const hex_map = new Map([
            ['0', 0], ['1', 1], ['2', 2], ['3', 3],
            ['4', 4], ['5', 5], ['6', 6], ['7', 7],
            ['8', 8], ['9', 9], ['a', 10], ['b', 11],
            ['c', 12], ['d', 13], ['e', 14], ['f', 15],
        ]);
        return color.match(/[a-f\d]{2}/gi).map(x => {
            return parseInt(hex_map.get(x[0].toLowerCase()) * 16 + hex_map.get(x[1].toLowerCase()));
        });
    }
    const [r1, g1, b1] = parse_hex(color1);
    const [r2, g2, b2] = parse_hex(color2);
    percent = Math.min(Math.max(percent, 0), 1);
    const nr = Math.round(r1 + (r2 - r1) * percent);
    const ng = Math.round(g1 + (g2 - g1) * percent);
    const nb = Math.round(b1 + (b2 - b1) * percent);
    return `rgb(${nr}, ${ng}, ${nb})`;
}