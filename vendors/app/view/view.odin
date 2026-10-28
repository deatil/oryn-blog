package view

import "core:os"
import "core:fmt"
import "core:time"
import "core:strings"
import "core:strconv"
import "core:encoding/json"

import "vendors:jinja"
import "vendors:app/global"

// ctx := jinja.dict()
// jinja.set(ctx, "title", jinja.str("Hello <World>"))
// jinja.set(ctx, "pages", jinja.list(jinja.str("a"), jinja.str("b")))
render :: proc(template: string, ctx: jinja.Value) -> (s: string, errstr: string) {
    t, err := jinja.load_template(global.view, template) 
    if err.kind != .None { 
		return "", jinja.format_error(err); 
	}

    out, rerr := jinja.render(&t, ctx)
    if rerr.kind != .None { 
		return "", jinja.format_error(rerr); 
	}

	return out, ""
}

// bytes := transmute([]byte)str
// str := transmute(string)bytes
read_file :: proc(name: string) -> (bytes: []byte, err: os.Error) {
	f: ^os.File

	f, err = os.open(name)
	if err != nil {
		return
	}

	sz: i64
	sz, err = os.file_size(f)
	if err != nil {
		return
	}

	bytes = make([]byte, sz)
	_, err = os.read_full(f, bytes)
	if err != nil {
		return
	}

	defer os.close(f)

	return
}

JSON_Map :: distinct map[string]JSON_Data
JSON_List :: distinct [dynamic]JSON_Data
JSON_Data :: union {
	JSON_Map,
	JSON_List,
	string,
}

marshal_json :: proc(v: any, opt: json.Marshal_Options = {}) -> (data: string, errstr: string) {
	datas, err := json.marshal(v, opt)
	if err != nil {
		return "", fmt.tprintf("%v", err)
	}

	return string(datas), ""
}

time_to_string :: proc(t: string) -> (str: string) {
	n, _ := strconv.parse_i64_of_base(t, 10)
	tt := time.unix(n, 0)

	buf: [time.MIN_YYYY_DATE_LEN]u8
	ymd_str := time.to_string_yyyy_mm_dd(tt, buf[:])

	buf2: [time.MIN_HMS_LEN]u8
	hms_str := time.to_string_hms(tt, buf2[:])

	time_str := fmt.tprintf("%s %s", ymd_str, hms_str)
	return time_str
}


