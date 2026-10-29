package view

import "oryn:http"
import "oryn:jinja"

import "oryn:app/global"
import "oryn:app/utils"

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

return_json :: proc(r: ^http.Response, v: any) {
	http.respond_json(r, v)
}

return_success :: proc(r: ^http.Response, message: string, data: any = "") {
	v := make(map[string]any)
	v["code"] = 0
	v["message"] = message
	v["data"] = data
	http.respond_json(r, v)
}

return_error :: proc(r: ^http.Response, message: string, code: int = 1) {
	v := make(map[string]any)
	v["code"] = code
	v["message"] = message
	http.respond_json(r, v)
}

add_functions :: proc() {
	jinja.add_function(global.view, "time_format", fn_time_format) 
}

fn_time_format :: proc(c: ^jinja.Call) -> jinja.Value {
	str := jinja.to_string(c.args[0])
	time_str := utils.time_to_string(str)

	return jinja.str(time_str) 
}

