package controller

import "core:fmt"
import "core:time"

import "vendors:http"
import "vendors:jinja"

import "vendors:app/view"
import "vendors:app/model"

User_Data :: struct {
	req: ^http.Request, 
	res: ^http.Response,
}

index :: proc(req: ^http.Request, res: ^http.Response) {
	items := model.get_commit_all()

	l := jinja.list()
	for item in items {
		d := jinja.dict()
		for k, v in item {
			jinja.set(d, k, jinja.str(v))
		}

		jinja.append_value(l, d)
	}

	ctx := jinja.dict()
	jinja.set(ctx, "data", l)

	output, _ := view.render("index.html", ctx)

	http.respond_html(res, output)
}

view :: proc(req: ^http.Request, res: ^http.Response) {
	id := req.url_params[0]
	item := model.get_commit_one(id)

	ctx := jinja.dict()
	jinja.set(ctx, "title", jinja.str(item["title"]))
	jinja.set(ctx, "content", jinja.str(item["content"]))
	jinja.set(ctx, "add_time", jinja.str(view.time_to_string(item["add_time"])))

	data := jinja.dict()
	jinja.set(data, "data", ctx)

	output, _ := view.render("view.html", data)
	http.respond_html(res, output)
}

edit :: proc(req: ^http.Request, res: ^http.Response) {
	id := req.url_params[0]
	item := model.get_commit_one(id)

	ctx := jinja.dict()
	jinja.set(ctx, "id", jinja.str(item["id"]))
	jinja.set(ctx, "title", jinja.str(item["title"]))
	jinja.set(ctx, "content", jinja.str(item["content"]))

	data := jinja.dict()
	jinja.set(data, "data", ctx)

	output, _ := view.render("edit.html", data)

	http.respond_html(res, output)
}

edit_save :: proc(req: ^http.Request, res: ^http.Response) {
	ud: User_Data
	ud.req = req
	ud.res = res

	http.body(req, 5000, &ud, proc(user_data: rawptr, body: http.Body, err: http.Body_Error) {
		ud2 := cast(^User_Data)user_data

		if err != nil {
			http.respond(ud2.res, http.body_error_status(err))
			return
		}

		form, _ := http.body_url_encoded(body)

		id := ud2.req.url_params[0]
		item := model.get_commit_one(id)
		if len(item) == 0 {
			http.respond_json(ud2.res, "edit error")
			return
		}
	
		data := make(map[string]string)
		data["title"] = form["title"]
		data["content"] = form["content"]
		data["add_time"] = fmt.tprintf("%v", time.time_to_unix(time.now()))

		ok := model.update_commit(id, data)
		if !ok {
			http.respond_json(ud2.res, "edit error")
			return
		}

		http.respond_json(ud2.res, "edit success")
	})
}

add :: proc(req: ^http.Request, res: ^http.Response) {
	data := jinja.dict()
	output, _ := view.render("add.html", data)

	http.respond_html(res, output)
}

add_save :: proc(req: ^http.Request, res: ^http.Response) {
	ud: User_Data
	ud.req = req
	ud.res = res

	http.body(req, 5000, &ud, proc(user_data: rawptr, body: http.Body, err: http.Body_Error) {
		ud2 := cast(^User_Data)user_data

		if err != nil {
			http.respond(ud2.res, http.body_error_status(err))
			return
		}

		form, _ := http.body_url_encoded(body)
	
		data := make(map[string]string)
		data["title"] = form["title"]
		data["content"] = form["content"]
		data["add_time"] = fmt.tprintf("%v", time.time_to_unix(time.now()))

		ok := model.add_commit(data)
		if !ok {
			http.respond_json(ud2.res, "add error")
			return
		}

		http.respond_json(ud2.res, "add success")
	})
}

del :: proc(req: ^http.Request, res: ^http.Response) {
	id := req.url_params[0]

	ok := model.delete_commit(id)
	if !ok {
		http.respond_json(res, "del error")
		return
	}

	http.respond_json(res, "del success")
}
