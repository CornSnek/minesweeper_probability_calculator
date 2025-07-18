import {
    PrintType, MsType, CalculateArray,
    CalculateStatus, Calculate, ProbabilityList,
    LocationCount, IDToLocationExtern, TileLocation, MineFrequency
} from './wasm_to_js.js'
let WasmObj = null;
let WasmExports = null;
let calculate_worker = null;
const WasmMemory = new WebAssembly.Memory({ initial: 20, maximum: 65536, shared: true });
let grid_body = null;
let tiles_palette;
let tile_description;
let tile_gui;
let all_right_tabs;
let tile_size_num;
let columns_num;
let rows_num;
let generate_grid;
let calculate_probability;
let clear_probability_button;
let clear_all_button;
let matrix_results_text;
let show_results_check;
let progress_div;
let calculate_progress;
let subsystem_progress;
let flash_body;
let flash_content;
let select_probability;
let gm_count;
let include_flags;
let patterns_list;
let patterns_table_of_contents;
let flood_fill;
let rows = null;
let columns = null;
let keybind_map = new Map();
let shift_key_down = false;
let ctrl_key_down = false;
const STATE_IDLE = 0;
const STATE_CALCULATING = 1;
const STATE_UPLOAD = 2;
let web_state = STATE_IDLE;
let tile_colors = {};
class UndoNode {
    constructor(x, y, ms_type) {
        this.x = x;
        this.y = y;
        this.ms_type = ms_type;
    }
}
class UndoQueue {
    static SIZE = 100;
    constructor() {
        this.buf = new Array(UndoQueue.SIZE).fill(null);
        this.next = 0;
    }
    push_undo(undo_node_arr) {
        this.buf[this.next] = undo_node_arr;
        this.next = (this.next + 1) % UndoQueue.SIZE;
    }
    pop_undo() {
        this.next = (UndoQueue.SIZE - 1 + this.next) % UndoQueue.SIZE;
        const undo_node_ret = this.buf[this.next];
        this.buf[this.next] = null;
        return undo_node_ret;
    }
    clear() {
        this.buf.fill(null);
        this.next = 0;
    }
}
const undo_queue = new UndoQueue();
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
    tile_size_num = document.getElementById('tile-size-num');
    columns_num = document.getElementById('columns-num');
    rows_num = document.getElementById('rows-num');
    generate_grid = document.getElementById('generate-grid');
    parse_screenshot_popup = document.getElementById('parse-screenshot-popup');
    calculate_probability = document.getElementById('calculate-probability');
    clear_probability_button = document.getElementById('clear-probability-button');
    clear_all_button = document.getElementById('clear-all-button');
    matrix_results_text = document.getElementById('matrix-results-text');
    show_results_check = document.getElementById('show-results-check');
    calculate_progress = document.getElementById('calculate-progress');
    subsystem_progress = document.getElementById('subsystem-progress');
    progress_div = document.getElementById('progress-div');
    flash_body = document.getElementById('flash-body');
    flash_content = document.getElementById('flash-content');
    select_probability = document.getElementById('select-probability');
    gm_count = document.getElementById('gm-count');
    include_flags = document.getElementById('include-flags');
    patterns_list = document.getElementById('patterns-list');
    patterns_table_of_contents = document.getElementById('patterns-table-of-contents');
    flood_fill = document.getElementById('flood-fill');
    upload_body = document.getElementById('upload-body');
    crop_left = document.getElementById('crop-left');
    crop_right = document.getElementById('crop-right');
    crop_up = document.getElementById('crop-up');
    crop_down = document.getElementById('crop-down');
    canvas_tile = document.getElementById('canvas-tile');
    canvas_screenshot = document.getElementById('canvas-screenshot');
    parse_screenshot = document.getElementById('parse-screenshot');
    cancel_parse_screenshot = document.getElementById('cancel-parse-screenshot');
    board_width_size = document.getElementById('board-width-size');
    upload_output = document.getElementById('upload-output');
    const root_comp = getComputedStyle(document.documentElement);
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
            image_div.onclick = assign_selected_f.bind({ tile: MsType[tile_name], selected_tile, set_undo_buffer: true });
            image_div.onmouseenter = () => {
                image_div.classList.add('tile-hovered');
                tile_description.textContent = MsType.$description[MsType[tile_name]];
            };
            image_div.onmouseleave = () => {
                image_div.classList.remove('tile-hovered');
                tile_description.innerHTML = get_default_tile_description();
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
    if (columns_num.validity.valid && rows_num.validity.valid) {
        init_grid(columns_num.value, rows_num.value);
    } else {
        init_grid(10, 10);
    }
    const UnshiftNums = new Map(
        [
            ['!', '1'],
            ['@', '2'],
            ['#', '3'],
            ['$', '4'],
            ['%', '5'],
            ['^', '6'],
            ['&', '7'],
            ['*', '8'],
            ['(', '9'],
            [')', '0']
        ])
        ;
    function unshift_key(ch) { ///For keybind_map because holding Shift capitalizes or replaces the letter for e.key
        return UnshiftNums.get(ch) ?? (ch.length === 1 ? ch.toLowerCase() : ch)
    }
    document.addEventListener('keydown', e => {
        if (!e.repeat) {
            if (e.key == 'Shift') {
                shift_key_down = true;
                flood_fill.checked = true;
            } else if (e.key == 'Control') {
                ctrl_key_down = true;
            } else if (e.key == 'Escape') {
                deselect_tiles_f(e);
                hide_any_right_panels(e);
            } else {
                if (shift_key_down) {
                    switch (e.key) {
                        case 'Enter':
                            calculate_probability_f(e);
                            break;
                        case 'Delete':
                            clear_all_tiles(e);
                            return; //Don't run the same keybind 'Delete' code
                    }
                }
                if (ctrl_key_down) {
                    switch (e.key) {
                        case 'c':
                            selected_tile.copy_text_clipboard(false);
                            break;
                        case 'x':
                            selected_tile.copy_text_clipboard(true);
                            break;
                        case 'z':
                            if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA' || e.target.isContentEditable) break;
                            e.preventDefault();
                            if (web_state != STATE_IDLE) break;
                            const undo_node_arr = undo_queue.pop_undo();
                            if (undo_node_arr !== null) {
                                for (const un of undo_node_arr) {
                                    set_tile(un.x, un.y, un.ms_type);
                                }
                            } else flash_message(FLASH_ERROR, 'Unable to Undo', 1000);
                            break;
                        case 'a':
                            if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA' || e.target.isContentEditable) break;
                            e.preventDefault();
                            if (web_state != STATE_IDLE) break;
                            tile_select_any_f.bind(new SelectedTile({
                                t: SelectedTile.Many, p: new TilePoint(0, 0), s: new TilePoint(columns, rows)
                            }))(e);
                            break;
                    }
                } else {
                    const fn = keybind_map.get(unshift_key(e.key));
                    if (fn !== undefined) {
                        fn(e);
                    }
                }
            }
        }
    });
    window.addEventListener('resize', e => {
        const tab = document.querySelector('.options-gui.panel-show');
        if (tab !== null) {
            document.querySelector(':root').style.setProperty('--all-tabs-shift', `-${tab.offsetWidth}px`);
            document.body.style.marginRight = `${all_right_tabs.offsetWidth + tab.offsetWidth}px`;
        }
    });
    document.addEventListener('keyup', e => {
        if (e.key == 'Shift') {
            shift_key_down = false;
            flood_fill.checked = false;
        } else if (e.key == 'Control') {
            ctrl_key_down = false;
        }
    });
    document.querySelectorAll('.close-options-panel').forEach(link => link.onclick = hide_any_right_panels);
    [...all_right_tabs.children].forEach(tab_elem => {
        const tab_id = tab_elem.dataset.tab;
        if (tab_id !== undefined) {
            tab_elem.onclick = (e) => toggle_right_tab(tab_elem, tab_id);
        }
    });
    tile_size_num.onchange = tile_size_f;
    tile_size_f();
    columns_num.onclick = deselect_tiles_f;
    rows_num.onclick = deselect_tiles_f;
    gm_count.onclick = deselect_tiles_f;
    generate_grid.onclick = e => {
        if (web_state != STATE_IDLE) return;
        if (!columns_num.validity.valid || !rows_num.validity.valid) {
            flash_message(FLASH_ERROR, "Number of Rows and Column should be limited from 1 to 100");
            return;
        }
        if (confirm('Are you sure? This will clear all tiles.')) {
            init_grid(parseInt(columns_num.value), parseInt(rows_num.value));
        }
    };
    calculate_probability.onclick = calculate_probability_f;
    parse_screenshot_popup.onclick = async e => {
        if (web_state == STATE_IDLE) {
            deselect_tiles_f();
            hide_any_right_panels(e);
            disable_upload_sliders(true);
            upload_output.textContent = '';
            show_upload_body();
        }
    }
    clear_probability_button.onclick = clear_all_probability;
    clear_all_button.onclick = clear_all_tiles;
    document.addEventListener('paste', e => selected_tile.paste_text_clipboard(e.clipboardData.getData('text')));
    document.body.style.marginRight = `${all_right_tabs.offsetWidth}px`;
    document.body.style.marginBottom = `${tile_gui.offsetHeight}px`;
    calculate_worker = new Worker("./calculate.js", { type: 'module' });
    calculate_worker.onerror = end_progress;
    calculate_worker.onmessage = e => {
        worker_handler_module[e.data[0]](...e.data.slice(1));
    };
    calculate_worker.postMessage(['m', WasmMemory]);
    patterns_table_of_contents.textContent = '<h3>Patterns List</h3><ul>';
    [...patterns_list.children].forEach(li => {
        const a_id = li.id;
        li.innerHTML += '<br><br><b><a href="#patterns-body">Back to Top</a></b>';
        const title = li.children[0].textContent;
        patterns_table_of_contents.textContent += `<li><b><a href="#${a_id}">${title}</a><b></li>`
    });
    //Adding this before li.innerHTML as it removes the .onclick listener
    document.querySelectorAll('#patterns-body .tile-template, #probability-body .tile-template').forEach(div => {
        create_board_pattern(div, div.dataset.ncolumns, div.dataset.str);
        div.onclick = e => {
            const copy_data = SelectedTile.ClipboardHeader + div.dataset.str.replace(/[cv]([.?]|\(.*?\))/g, 'c');
            navigator.clipboard.writeText(copy_data).catch(err => console.warn('Clipboard copy failed: ' + err));
            flash_message(FLASH_SUCCESS, 'Copied to Clipboard', 3000);
        };
    });
    patterns_table_of_contents.innerHTML = patterns_table_of_contents.textContent + '</ul>';
    flash_body.onclick = hide_flash;
    select_probability.onchange = e => {
        const prob_type = e.target.value;
        gm_count.disabled = prob_type !== 'Global';
        include_flags.disabled = prob_type !== 'Global';
        flash_message(FLASH_SUCCESS, (prob_type !== 'Global') ? 'Local shows only the probability for adjacent tiles' : 'Global shows the probability of the whole board, where Mine Count is considered', 5000);
    };
    include_flags.onchange = e => flash_message(FLASH_SUCCESS, e.target.checked ? 'Flags and mines are counted in Global Count to consider the total number of mines left + flags + mines in a board.' : 'Flags and mines are not counted in Global Count to consider only the number of mines left.', 5000);
    parse_screenshot.onclick = pre_parse_screenshot_board;
    crop_left.onchange = delay_show_crop;
    crop_left.onclick = delay_show_crop;
    crop_right.onchange = delay_show_crop;
    crop_right.onclick = delay_show_crop;
    crop_up.onchange = delay_show_crop;
    crop_up.onclick = delay_show_crop;
    crop_down.onchange = delay_show_crop;
    crop_down.onclick = delay_show_crop;
    board_width_size.onchange = delay_show_crop;
    cancel_parse_screenshot.onclick = () => {
        parse_screenshot.disabled = true;
        upload_body.style.display = 'none';
        web_state = STATE_IDLE;
    }
    gm_count.disabled = select_probability.value !== 'Global';
    include_flags.disabled = select_probability.value !== 'Global';
    console.log('Waiting for KaTeX module...');
    wait_katex();
}
const FLASH_ERROR = 0;
const FLASH_SUCCESS = 1;
let last_flash_timer = null;
function flash_message(type, message, hide_ms) {
    if (last_flash_timer !== null) {
        clearTimeout(last_flash_timer);
        last_flash_timer = null;
    }
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
    if (hide_ms !== undefined) {
        last_flash_timer = setTimeout(hide_flash, hide_ms);
    }
}
function hide_flash() {
    flash_body.style.display = 'none';
}
function tile_size_f(e) {
    const tile_size = Math.min(Math.max(parseInt(tile_size_num.value), 20), 100);
    tile_size_num.value = tile_size;
    document.body.style.setProperty('--size-tile', `${tile_size}px`);
    document.body.style.setProperty('--size-image', `${tile_size * 3 / 4}px`);
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
function toggle_right_tab(tab_elem, tab_id) {
    deselect_tiles_f();
    const tab = document.getElementById(tab_id);
    const last_tab = document.querySelector('.options-gui.panel-show');
    hide_any_right_panels();
    if (tab === last_tab) return; //Close if same tab
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
    deselect_tiles_f();
    undo_queue.clear();
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
            if (web_state != STATE_IDLE) return;
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
        const array = [];
        switch (this.type) {
            case SelectedTile.One:
                console.assert(grid_body != null && columns != null, 'grid_body and columns must not be null');
                array.push(grid_body.children[this.select.y * columns + this.select.x]);
                break;
            case SelectedTile.Many:
                console.assert(grid_body != null && columns != null, 'grid_body and columns must not be null');
                for (let j = this.select.p.y; j < this.select.p.y + this.select.s.y; j++) {
                    for (let i = this.select.p.x; i < this.select.p.x + this.select.s.x; i++) {
                        array.push(grid_body.children[j * columns + i]);
                    }
                }
        }
        return array;
    }
    center_view() {
        console.assert(grid_body != null && columns != null, 'grid_body and columns must not be null');
        const scroll_obj = {
            behavior: 'smooth',
            block: 'center',
            inline: 'center'
        };
        if (this.type === SelectedTile.One) {
            const tile = grid_body.children[this.select.y * columns + this.select.x];
            const tile_rect = tile.getBoundingClientRect();
            const grid_body_rect = grid_body.getBoundingClientRect();
            const lr_visible = tile_rect.left >= grid_body_rect.left && tile_rect.right <= grid_body_rect.right;
            const mb = parseInt(document.body.style.marginBottom);
            const ud_visible = tile_rect.top >= 0 && tile_rect.bottom <= window.innerHeight - mb;
            if (!lr_visible || !ud_visible) tile.scrollIntoView(scroll_obj);
        } else if (this.type === SelectedTile.Many) {
            const ultile = grid_body.children[this.select.p.y * columns + this.select.p.x];
            const urtile = grid_body.children[this.select.p.y * columns + this.select.p.x + this.select.s.x - 1];
            const bltile = grid_body.children[(this.select.p.y + this.select.s.y - 1) * columns + this.select.p.x];
            const ultile_rect = ultile.getBoundingClientRect();
            const urtile_rect = urtile.getBoundingClientRect();
            const bltile_rect = bltile.getBoundingClientRect();
            const grid_body_rect = grid_body.getBoundingClientRect();
            const mb = parseInt(document.body.style.marginBottom);
            if (ultile_rect.top < 0 || ultile_rect.left < grid_body_rect.left) ultile.scrollIntoView(scroll_obj);
            if (bltile_rect.bottom > window.innerHeight - mb) bltile.scrollIntoView(scroll_obj);
            if (urtile_rect.right > grid_body_rect.right) urtile.scrollIntoView(scroll_obj);
        }
    }
    move(new_st) {
        this.type = new_st.type;
        this.select = new_st.select;
    }
    copy_text_clipboard(clear_data) {
        console.assert(grid_body != null, 'grid_body must not be null');
        let copy_data = SelectedTile.ClipboardHeader;
        const undo_node_arr = [];
        if (this.type == SelectedTile.One) {
            const div = grid_body.children[this.select.y * columns + this.select.x];
            copy_data += MsType.$js_ch[div.dataset.ms_type] + ',';
        } else if (this.type == SelectedTile.Many) {
            for (let j = this.select.p.y; j < this.select.p.y + this.select.s.y; j++) {
                for (let i = this.select.p.x; i < this.select.p.x + this.select.s.x; i++) {
                    const div = grid_body.children[j * columns + i];
                    copy_data += MsType.$js_ch[div.dataset.ms_type];
                    if (clear_data)
                        undo_node_arr.push(...assign_selected_f.bind({
                            tile: MsType.unknown, selected_tile: new SelectedTile({
                                t: SelectedTile.One, p: new TilePoint(i, j)
                            })
                        })());
                }
                copy_data += ',';
            }
        }
        if (undo_node_arr.length !== 0) {
            undo_queue.push_undo(undo_node_arr);
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
            const undo_node_arr = []
            for (let ch_i = 0; ch_i < pasted_text.length; ch_i++) {
                let tile_enum;
                if ((tile_enum = ch_to_tile_enum.get(pasted_text[ch_i])) !== undefined) {
                    if (tp.x < columns && tp.y < rows) {
                        undo_node_arr.push(...assign_selected_f.bind({
                            tile: tile_enum, selected_tile: new SelectedTile({
                                t: SelectedTile.One, p: new TilePoint(tp.x, tp.y)
                            })
                        })());
                        tp_end = new TilePoint(tp.x, tp.y);
                    }
                }
                if (pasted_text[ch_i] === ',') {
                    tp.y += 1;
                    tp.x = tp_old_x;
                } else tp.x += 1;
            }
            undo_queue.push_undo(undo_node_arr);
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
        flood_fill.checked = false;
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
    tile_description.innerHTML = get_default_tile_description();
    const down_f = e => {
        e.preventDefault();
        selected_tile.center_view();
        deselect_tiles_f(e);
        this.shift(SelectedTile.Down);
        tile_select_any_f.bind(this)(e);
    };
    const up_f = e => {
        e.preventDefault();
        selected_tile.center_view();
        deselect_tiles_f(e);
        this.shift(SelectedTile.Up);
        tile_select_any_f.bind(this)(e);
    };
    const left_f = e => {
        e.preventDefault();
        selected_tile.center_view();
        deselect_tiles_f(e);
        this.shift(SelectedTile.Left);
        tile_select_any_f.bind(this)(e);
    };
    const right_f = e => {
        e.preventDefault();
        selected_tile.center_view();
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
        keybind_map.set(ch, assign_selected_f.bind({ tile, selected_tile, set_undo_buffer: true }));
    }
    keybind_map.set('Delete', assign_selected_f.bind({ tile: MsType.unknown, selected_tile, set_undo_buffer: true }));
}
///ord_fn is 0 if lhs is equal to rhs, negative if less than, or positive if greater than
function binary_search(arr, target, ord_fn) {
    let left = 0;
    let right = arr.length - 1;
    while (left <= right) {
        const mid = Math.floor((left + right) / 2);
        if (ord_fn(arr[mid], target) == 0) return mid;
        else if (ord_fn(arr[mid], target) < 0) left = mid + 1;
        else right = mid - 1;
    }
    return -1;
}
function undo_node_ord(lhs, rhs) {
    return lhs.y * columns + lhs.x - rhs.y * columns - rhs.x;
}
function assign_selected_f(e) {
    let undo_node_arr = [];
    if (!flood_fill.checked || this.no_flood_fill) {
        for (const div of this.selected_tile.get_div_array()) {
            const x = parseInt(div.dataset.x);
            const y = parseInt(div.dataset.y);
            const old_type = WasmExports.QueryTile(x, y);
            undo_node_arr.push(new UndoNode(x, y, old_type));
            set_tile(x, y, this.tile);
        }
    } else {
        if (selected_tile.type === SelectedTile.Many)
            if (!confirm('Selecting more than one tile and using flood fill is not recommended. Continue?')) return undo_node_arr;
        for (const div of this.selected_tile.get_div_array()) {
            const i_set_visited = new Set();
            const stack_i = [];
            const x = parseInt(div.dataset.x);
            const y = parseInt(div.dataset.y);
            const i = y * columns + x;
            const to_fill_mstype = WasmExports.QueryTile(x, y);
            stack_i.push(i);
            while (stack_i.length !== 0) {
                const this_i = stack_i.pop();
                if (i_set_visited.has(this_i)) continue;
                i_set_visited.add(this_i);
                const this_x = this_i % columns;
                const this_y = Math.floor(this_i / columns);
                const cmp_mstype = WasmExports.QueryTile(this_x, this_y);
                if (cmp_mstype !== to_fill_mstype) continue;
                const ua = new UndoNode(this_x, this_y, cmp_mstype);
                if (binary_search(undo_node_arr, ua, undo_node_ord) === -1) { //Uniquely add each tile by binary search/sort
                    undo_node_arr.push(ua);
                    undo_node_arr.sort(undo_node_ord);
                }
                set_tile(this_x, this_y, this.tile);
                if (this_x + 1 != columns) {
                    const ri = this_y * columns + (this_x + 1);
                    stack_i.push(ri);
                }
                if (this_x - 1 >= 0) {
                    const li = this_y * columns + (this_x - 1);
                    stack_i.push(li);
                }
                if (this_y + 1 != rows) {
                    const di = (this_y + 1) * columns + this_x;
                    stack_i.push(di);
                }
                if (this_y - 1 >= 0) {
                    const ui = (this_y - 1) * columns + this_x;
                    stack_i.push(ui);
                }
            }
        }
    }
    if (this.set_undo_buffer !== undefined) undo_queue.push_undo(undo_node_arr);
    return undo_node_arr;
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
    div.appendChild(img);
    img.src = 'images/' + image_url;
    img.classList.add('img-tile');
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
const shift_p_enter = '<strong class="badge">Shift</strong>+<strong class="badge">Enter</strong>';
function calculate_probability_f(e) {
    if (web_state == STATE_IDLE) {
        hide_flash();
        start_progress();
        deselect_tiles_f();
        calculate_worker.postMessage(['f', 'CalculateProbability']);
        SetTimeoutProgress(0, 0.0);
        calculate_probability.innerHTML = `Cancel Calculation ${shift_p_enter}`;
    } else if (web_state == STATE_CALCULATING) {
        Atomics.store(new Uint8Array(WasmMemory.buffer), WasmExports.CancelCalculation.value, 1);
        flash_message(FLASH_ERROR, 'Cancelled Calculation');
    }
}
function clear_all_tiles(e) {
    if (web_state != STATE_IDLE) return;
    assign_selected_f.bind({
        tile: MsType.unknown,
        selected_tile: new SelectedTile({
            t: SelectedTile.Many, p: new TilePoint(0, 0), s: new TilePoint(columns, rows)
        }),
        set_undo_buffer: true,
        no_flood_fill: true
    })();
};
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
    delete div.dataset.freq_a;
    delete div.dataset.freq_na;
}
function get_default_tile_description() {
    console.assert(grid_body != null && columns != null, 'grid_body and columns must not be null');
    let td = '';
    if (selected_tile.type === SelectedTile.One) {
        const div = grid_body.children[selected_tile.select.y * columns + selected_tile.select.x];
        td += `(x:${selected_tile.select.x},y:${selected_tile.select.y})`;
        let status;
        if ((status = div.dataset.error) !== undefined) {
            td += `<br>${CalculateStatus.$error_message[status]}`;
        } else if ((status = div.dataset.freq_a) !== undefined) {
            const map_regex = /([t\d]+G?):=(\d+)\./g;
            const START = 0;
            const TILE = 1;
            const SYSTEM = 2;
            let parse_state = START;
            let match;
            while ((match = map_regex.exec(status)) !== null) {
                const m_str = match[1];
                const f_str = match[2];
                switch (parse_state) {
                    case START:
                        console.assert(m_str === 't', 'freq_a should start with t.');
                        td += `, ${f_str} total solution(s). Tile Mine Frequency [ `;
                        parse_state = TILE;
                        break;
                    case TILE:
                        if (!m_str.endsWith('G')) {
                            td += `(${f_str} s &rarr; ${m_str} m), `;
                            break;
                        }
                        parse_state = SYSTEM;
                        td += `] Board Mine Frequency [`
                    case SYSTEM:
                        td += `(${f_str} s &rarr; ${m_str.slice(0, -1)} m), `;
                }
            }
            td += ']';
        } else if ((status = div.dataset.freq_na) !== undefined) {
            td += `<br>Non-adjacent tile count: ${status}`;
        }
    } else if (selected_tile.type === SelectedTile.Many) {
        td += `(x:${selected_tile.select.p.x},y:${selected_tile.select.p.y}):(x:${selected_tile.select.p.x + selected_tile.select.s.x - 1},y:${selected_tile.select.p.y + selected_tile.select.s.y - 1})<br>`;
    }
    return td;
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
    //Global Mine Probability
    gm_probability() {
        let gmfg = null;
        if (this.global.length !== 0) gmfg = this.global[0].map;
        let mine_count_adj = parseInt(gm_count.value);
        let mine_flag_count = 0;
        let adjacent_tiles = 0;
        this.local.forEach(mfg_arr => adjacent_tiles += mfg_arr.length);
        let non_adjacent_tiles = 0;
        [...grid_body.children].forEach(div => {
            const ms_type = div.dataset.ms_type;
            non_adjacent_tiles += ms_type == MsType.unknown;
            if (include_flags.checked) {
                const is_mine_or_flag = ms_type == MsType.mine || ms_type == MsType.flag;
                mine_count_adj -= is_mine_or_flag;
                mine_flag_count += is_mine_or_flag;
            }
        });
        if (mine_count_adj < 0) {
            if (include_flags.checked) {
                flash_message(FLASH_ERROR, `Error: The mines + flags placed (${mine_flag_count}) exceeds the global mine count (${mine_count_adj + mine_flag_count}).`);
            } else {
                flash_message(FLASH_ERROR, `Error: Global mine count is less than 0.`);
            }
            return;
        }
        non_adjacent_tiles -= adjacent_tiles;
        //console.log(`AT: ${adjacent_tiles}, NAT: ${non_adjacent_tiles}`);
        let a_denominator = 0n;
        let na_denominator = 0n;
        let na_numerator = 0n;
        let max_gm = 0;
        let min_gm = Infinity;
        if (gmfg !== null) {
            let too_many_skip = 0;
            let gf_sum = 0n;
            for (const [gm, gf] of gmfg) {
                min_gm = Math.min(min_gm, gm);
                if (gm > mine_count_adj) {
                    too_many_skip++;
                    continue;
                }
                a_denominator += gf * comb(non_adjacent_tiles, mine_count_adj - gm);
                //Discard solutions that have too little mines and would overfill non adjacent tiles.
                if (mine_count_adj <= non_adjacent_tiles + gm) {
                    na_numerator += BigInt(mine_count_adj - gm) * gf;
                    gf_sum += gf;
                }
                max_gm = Math.max(max_gm, gm);
            }
            na_denominator = BigInt(non_adjacent_tiles) * gf_sum;
            if (gmfg.size != 0 && gmfg.size == too_many_skip) {
                if (include_flags.checked) {
                    flash_message(FLASH_ERROR, `Error: Too little mines! The global mine count is ${mine_count_adj + mine_flag_count} - (${mine_flag_count} mines + flags) = ${mine_count_adj}. All solutions require at least ${min_gm} or more mines. Global mine count must be >= ${min_gm + mine_flag_count}.`);
                } else {
                    flash_message(FLASH_ERROR, `Error: Too little mines! The global mine count is ${mine_count_adj}. All solutions require at least ${min_gm} or more mines. Global mine count must be >= ${min_gm}.`);
                }
                return;
            }
            if (a_denominator === 0n) {
                if (include_flags.checked) {
                    flash_message(FLASH_ERROR, `Error: Too many mines! The global mine count is ${mine_count_adj + mine_flag_count} - (${mine_flag_count} mines + flags) = ${mine_count_adj}. One solution has a maximum of ${max_gm} mines and there are only ${non_adjacent_tiles} non-adjacent tiles to fill, resulting in the sum of only ${max_gm + non_adjacent_tiles} mines. Global mine count must be <= ${max_gm + non_adjacent_tiles + mine_flag_count}.`);
                } else {
                    flash_message(FLASH_ERROR, `Error: Too many mines! The global mine count is ${mine_count_adj}. One solution has a maximum of ${max_gm} mines and there are only ${non_adjacent_tiles} non-adjacent tiles to fill, resulting in the sum of only ${max_gm + non_adjacent_tiles} mines. Global mine count must be <= ${max_gm + non_adjacent_tiles}.`);
                }
                return;
            }
        }
        this.local.forEach(mfg_arr => {
            mfg_arr.forEach(mfg => {
                let a_numerator = 0n;
                for (const [gm, gf] of mfg.map) {
                    if (gm > mine_count_adj) continue;
                    a_numerator += gf * comb(non_adjacent_tiles, mine_count_adj - gm);
                }
                const pb = format_percentage(a_numerator, a_denominator);
                const x = mfg.x;
                const y = mfg.y;
                const div = grid_body.children[y * columns + x];
                div.textContent = `\\( \\htmlStyle{font-size: 0.75em}{${pb}\\\%} \\)`;
                renderMathInElement(div, {
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
                    let tc = (percentage <= 0.5)
                        ? color_lerp(tile_colors.clear, tile_colors.neutral, percentage * 2)
                        : color_lerp(tile_colors.neutral, tile_colors.mine, percentage * 2 - 1);
                    div.style.setProperty('--tile-color', tc);
                }
                div.dataset.probability = 'y';
            });
        });
        //Probability of an empty matrix (No adjacent tiles) is just (number of mines)/(number of non-adjacent tiles)
        if (this.global.length === 0) {
            if (mine_count_adj > non_adjacent_tiles) {
                if (include_flags.checked) {
                    flash_message(FLASH_ERROR, `Error: Too many mines! The global mine count is ${mine_count_adj + mine_flag_count} - (${mine_flag_count} mines + flags) = ${mine_count_adj}. There are only ${non_adjacent_tiles} non-adjacent tiles that can be mines. Global mine count must be <= ${mine_flag_count + non_adjacent_tiles}.`);
                } else {
                    flash_message(FLASH_ERROR, `Error: Too many mines! The global mine count is ${mine_count_adj}. There are only ${non_adjacent_tiles} non-adjacent tiles that can be mines. Global mine count must be <= ${non_adjacent_tiles}.`);
                }
                return;
            }
            na_denominator = non_adjacent_tiles;
            na_numerator = mine_count_adj;
        }
        //console.log(na_numerator, na_denominator, (100 * Number(na_numerator) / Number(na_denominator)).toFixed(2));
        [...grid_body.children].forEach(div => { //Fill Non-adjacent unknown tiles with the same probability
            if (div.dataset.ms_type == MsType.unknown && div.dataset.probability === undefined) {
                const pb = format_percentage(na_numerator, na_denominator);
                div.textContent = `\\( \\htmlStyle{font-size: 0.75em}{${pb}\\\%} \\)`;
                renderMathInElement(div, {
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
                    let tc = (percentage <= 0.5)
                        ? color_lerp(tile_colors.clear, tile_colors.neutral, percentage * 2)
                        : color_lerp(tile_colors.neutral, tile_colors.mine, percentage * 2 - 1);
                    div.style.setProperty('--tile-color', tc);
                }
                div.dataset.freq_na = non_adjacent_tiles;
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
        toggle_right_tab(results_tab_button, 'results-tab');
    }
    const calc_arr = new DataView(WasmMemory.buffer, c_arr_ptr, CalculateArray.$size);
    const calc_arr_status = calc_arr.getUint8(CalculateArray.status.offset, true);
    if (calc_arr_status == CalculateStatus.ok) {
        const ca_recalculated = calc_arr.getUint8(CalculateArray.recalculated.offset, true);
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
                    const div = grid_body.children[y * columns + x];
                    div.dataset.freq_a = `t:=${total_solutions}.`;
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
                            div.dataset.freq_a += `${m}:=${f}.`;
                            mfg.assign_mf(m, f);
                        }
                    }
                    mfg_list.add_local(ca_i, mfg);
                    if (select_probability.value !== 'Global') {
                        div.textContent = select_probability.value === 'Local'
                            ? `\\( \\frac{${count}}{${total_solutions}} \\)`
                            : `\\( \\htmlStyle{font-size: 0.75em}{${format_percentage(count, total_solutions)}\\\%} \\)`;
                        renderMathInElement(div, {
                            trust: true,
                            strict: (code) => code === "htmlExtension" ? "ignore" : "warn",
                        });
                        if (count == total_solutions)
                            div.classList.add('tile-pb-mine');
                        else if (count == 0)
                            div.classList.add('tile-pb-clear');
                        else {
                            div.classList.add('tile-pb-color');
                            const percentage = count / total_solutions;
                            let tc = (percentage <= 0.5)
                                ? color_lerp(tile_colors.clear, tile_colors.neutral, percentage * 2)
                                : color_lerp(tile_colors.neutral, tile_colors.mine, percentage * 2 - 1);
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
                    for (let lc_i = 0; lc_i < lc_len; lc_i++) {
                        const x = lc.getUint32(lc_i * LocationCount.$size + LocationCount.x.offset, true);
                        const y = lc.getUint32(lc_i * LocationCount.$size + LocationCount.y.offset, true);
                        const div = grid_body.children[y * columns + x];
                        div.dataset.freq_a += `${m}G:=${f}.`;
                    }
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
        if (mfg_list.convolve_all()) {
            let total_num = 0n;
            if (mfg_list.global.length !== 0) {
                if (ca_recalculated === 1 && mfg_list.global.length !== 1) {
                    AppendResults('Whole System<br>');
                    const first_map = mfg_list.global[0];
                    for (const [_, f] of first_map.map) {
                        total_num += f;
                    }
                    AppendResults(`Total valid solutions found for this system: ${total_num.toLocaleString()}<br>`);
                    for (const [m, f] of first_map.map) {
                        AppendResults(`${f.toLocaleString()} solution(s) have ${m} total mines.<br>`);
                    }
                }
            }
            if (select_probability.value === 'Global') mfg_list.gm_probability();
        }
    } else {
        flash_message(FLASH_ERROR, 'Encountered an error: \'' + CalculateStatus.$error_message[calc_arr_status]) + '\'';
    }
}
function ClearResults() {
    matrix_results_text.innerHTML = 'Probability Results<br><br>';
}
function AppendResults(string) {
    matrix_results_text.innerHTML += string;
}
function FinalizeResults() {
    renderMathInElement(matrix_results_text);
}
let debounce_timeout = false;
function start_progress() {
    web_state = STATE_CALCULATING;
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
        renderMathInElement(matrix_results_text);
    }, 1000);
    subsystem_progress.value = subsystem_id + 1;
    calculate_progress.value = progress;
}
function end_progress() {
    web_state = STATE_IDLE;
    calculate_progress.value = 1;
    progress_div.style.display = 'none';
    calculate_probability.innerHTML = `Calculate Probability ${shift_p_enter}`;
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
            } else if (next_ch == '(') {
                if (tile_enum == MsType.unknown) {
                    const end = tile_string.indexOf(')', ch_i + 1);
                    if (end !== -1) {
                        const text_slice = tile_string.slice(ch_i + 2, end);
                        tile_div.textContent = `\\( ${text_slice} \\)`;
                        renderMathInElement(tile_div);
                    } else throw Error(`Missing ')'`);
                    ch_i += end - ch_i;
                } else {
                    console.error(`Character '${this_ch}' and ) is only used for unknowns to inline text`);
                }
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
let upload_body;
let parse_screenshot_popup;
let canvas_tile;
let canvas_screenshot;
let parse_screenshot;
let cancel_parse_screenshot;
let board_width_size;
let upload_output;
let session = null;
document.addEventListener('dragover', e => {
    e.preventDefault();
    parse_screenshot.disabled = true;
    upload_body.style.display = 'block';
    disable_upload_sliders(true);
});
document.addEventListener('drop', async e => {
    e.preventDefault();
    const files = e.dataTransfer.files;
    if (files.length > 0) {
        if (files[0] && files[0].type.startsWith("image/")) {
            await show_upload_body(files[0]);
        }
    }
});
//Should be same order as image_ai/labels.py
const class_labels = ['unknown', 'mine', 'flag', '0', '1', '2', '3', '4', '5', '6', '7', '8'];
const img_screenshot = new Image();
let last_image_file = null;
let reset_crop_values = true; //Don't clear values if using the same file.
img_screenshot.onload = () => {
    if (reset_crop_values) {
        crop_left.value = 0;
        crop_right.value = 0;
        crop_up.value = 0;
        crop_down.value = 0;
        board_width_size.value = 10;
    }
    disable_upload_sliders(false);
    web_state = STATE_UPLOAD;
    show_crop();
}
function disable_upload_sliders(b) {
    crop_left.disabled = b;
    crop_right.disabled = b;
    crop_up.disabled = b;
    crop_down.disabled = b;
    board_width_size.disabled = b;
}
async function show_upload_body(file) {
    web_state = STATE_UPLOAD;
    upload_body.style.display = 'block';
    deselect_tiles_f();
    hide_any_right_panels();
    if (flood_fill.checked) flood_fill.checked = false;
    canvas_screenshot.width = 0;
    canvas_screenshot.height = 0;
    if (file === undefined && last_image_file !== null) {
        reset_crop_values = false;
        img_screenshot.src = URL.createObjectURL(last_image_file);
    } else if (file !== undefined && last_image_file !== null) {
        reset_crop_values = (file.name !== last_image_file.name
            || file.lastModified !== last_image_file.lastModified
            || file.size !== last_image_file.size
        ) //Only reset if different file.
        last_image_file = file;
        img_screenshot.src = URL.createObjectURL(file);
    } else if (file !== undefined && last_image_file === null) {
        reset_crop_values = true;
        last_image_file = file;
        img_screenshot.src = URL.createObjectURL(file);
    }
}
let crop_left;
let crop_right;
let crop_up;
let crop_down;
let crop_timer = null;
function delay_show_crop() {
    if (crop_timer !== null) {
        clearTimeout(crop_timer);
        crop_timer = null;
    }
    crop_timer = setTimeout(show_crop, 500);
    parse_screenshot.disabled = true;
}
function show_crop() {
    crop_timer = null;
    const cl = parseInt(crop_left.value);
    const cr = parseInt(crop_right.value);
    const cu = parseInt(crop_up.value);
    const cd = parseInt(crop_down.value);
    canvas_screenshot.width = img_screenshot.width;
    canvas_screenshot.height = img_screenshot.height;
    const ctx = canvas_screenshot.getContext('2d');
    ctx.clearRect(0, 0, img_screenshot.width, img_screenshot.height);
    ctx.drawImage(img_screenshot, 0, 0, img_screenshot.width, img_screenshot.height);
    ctx.fillStyle = 'rgba(0, 0, 0, 0.5)';
    ctx.fillRect(0, 0, cl, img_screenshot.height - cd);
    ctx.fillRect(cl, 0, img_screenshot.width - cl, cu);
    ctx.fillRect(img_screenshot.width - cr, cu, cr, img_screenshot.height - cu);
    ctx.fillRect(0, img_screenshot.height - cd, img_screenshot.width - cr, cd);
    const img_columns = parseInt(board_width_size.value);
    const tile_pixel_size = (img_screenshot.width - cl - cr) / img_columns;
    const img_rows = Math.round((img_screenshot.height - cu - cd) / tile_pixel_size);
    upload_output.textContent = `Calculating: ${img_columns} x ${img_rows} board with ${tile_pixel_size}px tile size.`;
    if (img_rows > 100 || img_rows <= 0) {
        flash_message(FLASH_ERROR, 'Detected invalid number of rows in screenshot. Must be from 1 to 100.');
        return;
    }
    if (cl + cr >= img_screenshot.width || cu + cd >= img_screenshot.height) {
        flash_message(FLASH_ERROR, 'Crop size must be less than the size of the image.', 3000);
        return;
    }
    parse_screenshot.disabled = false;
}
function tile_to_tensor(tile) {
    const gray = new Float32Array(1 * 1 * 32 * 32);
    for (let i = 0; i < 32 * 32; i++) {
        const r = tile[i * 4];
        const g = tile[i * 4 + 1];
        const b = tile[i * 4 + 2];
        const lum = (r + g + b) / 3 / 255;
        gray[i] = (lum - 0.5) / 0.5;
    }
    return new ort.Tensor("float32", gray, [1, 1, 32, 32]);
}
///Inputs already checked/validated in show_crop.
async function pre_parse_screenshot_board() {
    const img_columns = parseInt(board_width_size.value);
    const cl = parseInt(crop_left.value);
    const cr = parseInt(crop_right.value);
    const cu = parseInt(crop_up.value);
    const cd = parseInt(crop_down.value);
    const tile_pixel_size = (img_screenshot.width - cl - cr) / img_columns;
    const img_rows = Math.round((img_screenshot.height - cu - cd) / tile_pixel_size);
    columns_num.value = img_columns;
    rows_num.value = img_rows;
    init_grid(parseInt(img_columns), parseInt(img_rows));
    parse_screenshot.disabled = true;
    await parse_screenshot_board(img_rows, img_columns, tile_pixel_size, cl, cu);
    upload_body.style.display = 'none';
    web_state = STATE_IDLE;
}
async function parse_screenshot_board(img_rows, img_columns, tile_pixel_size, cl, cu) {
    if (!session) session = await ort.InferenceSession.create('model.onnx');
    const tile_ctx = canvas_tile.getContext('2d');
    let tile_string = SelectedTile.ClipboardHeader;
    for (let y = 0; y < img_rows; y++) {
        for (let x = 0; x < img_columns; x++) {
            const sx = x * tile_pixel_size;
            const sy = y * tile_pixel_size;
            tile_ctx.clearRect(0, 0, 32, 32);
            tile_ctx.drawImage(img_screenshot, cl + sx, cu + sy, tile_pixel_size, tile_pixel_size, 0, 0, 32, 32);
            const input_tensor = tile_to_tensor(tile_ctx.getImageData(0, 0, 32, 32).data);
            const result = await session.run({ input: input_tensor });
            const prediction = result.output.data;
            const pred_class = prediction.indexOf(Math.max(...prediction));
            const ms_type_str = class_labels[pred_class];
            tile_string += MsType.$js_ch[MsType[ms_type_str]];
        }
        tile_string += ',';
    }
    tile_select_any_f.bind(new SelectedTile({
        t: SelectedTile.One, p: new TilePoint(0, 0)
    }))(undefined);
    selected_tile.paste_text_clipboard(tile_string);
    deselect_tiles_f(undefined);
    flash_message(FLASH_SUCCESS, 'Completed parsing tiles from screenshot. Please check your screenshot for any incorrect tiles. You can try to reopen Parse Minesweeper Screenshot again to readjust crop values and board width.', 10000);
}