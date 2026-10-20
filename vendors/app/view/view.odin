package view

import "core:os"
import "core:fmt"
import "core:encoding/json"

import "vendors:mustache"

// import "core:fmt"
// import "core:encoding/json"
//
// datas, _ :=json.marshal(items)
// fmt.println(transmute(string)datas)
render :: proc(template: string, data: any) -> (s: string, errstr: string) {
	tpl, err := read_file(template)
	if err != nil {
		return "", os.error_string(err)
	}

	output, err2 := mustache.render(transmute(string)tpl, data)
	if err2 != nil {
		return "", fmt.tprintf("%v", err2)
	}

	return output, ""
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

load_json_string :: proc(val: string) -> (loaded: JSON_Data, errstr: string) {
	v, err := json.parse_string(val)
	if err != nil {
		return nil, fmt.tprintf("%v", err)
	}

	data := load_json(v)
	return data, ""
}

load_json :: proc(val: json.Value) -> (loaded: JSON_Data) {
	context.allocator = context.temp_allocator

	switch _val in val {
	case bool, string:
		v := fmt.tprintf("%v", _val)
		loaded = v
	case i64, f64:
		str := fmt.tprintf("%.2f", val)
		decimal_str := mustache.trim_decimal_string(str)
		loaded = decimal_str
	case json.Object:
		data := make(JSON_Map)
		for k, v in _val {
			new_k := fmt.tprintf("%v", k)
			data[new_k] = load_json(v)
		}
		loaded = data
	case json.Array:
		data := make(JSON_List)
		for v in _val {
			append(&data, load_json(v))
		}
		loaded = data
	case json.Null:
	}

	return loaded
}

