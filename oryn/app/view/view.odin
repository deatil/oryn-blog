package view

import "core:fmt"
import "core:time"
import "core:encoding/json"

import "oryn:jinja"
import gh "oryn:gjallarhorn"

import "oryn:app/global"
import "oryn:app/utils"

return_html :: proc(b: ^gh.Bifrost, body: string) {
	gh.write_response(b, 200, "text/html", body)
}

return_text :: proc(b: ^gh.Bifrost, body: string) {
	gh.text(b, 200, body)
}

return_json_raw :: proc(b: ^gh.Bifrost, body: string) {
	gh.write_response(b, 200, "application/json", body)
}

return_json :: proc(b: ^gh.Bifrost, v: any) {
	gh.json(b, 200, v)
}

return_success :: proc(b: ^gh.Bifrost, message: string, data: json.Value = "") {
	v := make(map[string]json.Value)
	v["code"] = 0
	v["message"] = message
	v["data"] = data

	return_json(b, v)
}

return_error :: proc(b: ^gh.Bifrost, message: string, code: i64 = 1) {
	v := make(map[string]json.Value)
	v["code"] = code
	v["message"] = message

	return_json(b, v)
}

redirect :: proc(b: ^gh.Bifrost, url: string) {
	gh.redirect(b, url)
}

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

add_functions :: proc() {
	jinja.add_function(global.view, "time_format", fn_time_format) 
	jinja.add_function(global.view, "now_time", fn_now_time) 
}

fn_time_format :: proc(c: ^jinja.Call) -> jinja.Value {
	str := jinja.to_string(c.args[0])
	time_str := utils.time_to_string(str)

	return jinja.str(time_str) 
}

fn_now_time :: proc(c: ^jinja.Call) -> jinja.Value {
	now := time.now()
	str := fmt.tprintf("%v", time.to_unix_seconds(now))
	time_str := utils.time_to_string(str)

	return jinja.str(time_str) 
}

